import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;
import 'upload_Para.dart';
import 'package:flutter/material.dart'; 
import 'upload_L1B.dart'; // 添加: 导入新的文件处理器模块
import 'package:mysql_client/mysql_client.dart';


// 定义 _readSettings 方法
Future<Map<String, dynamic>> _readSettings() async {
  final settingsFile = File('settings.json');
  final settingsContent = await settingsFile.readAsString();
  return json.decode(settingsContent);
}

// 遍历文件夹并处理数据
void processFiles(BuildContext context) async { // 修改: 添加 BuildContext 参数
  // 读取设置
  final settings = await _readSettings();
  final showName = settings['show_name'];
  final name = settings['name'];
  final platformId = settings['Platform_id'];

  // 定义数据库连接参数
  final dbParams = ConnectionSettings(
    host: settings['databaseAddress'],
    port: int.parse(settings['databasePort']),
    user: settings['databaseUsername'],
    password: settings['databasePassword'],
    db: settings['databaseName'],
  );

  // 定义需要读取的文件夹路径
  final folderPath = settings['sourceDataPath'];

  // 记录程序开始时间
  final startTime = DateTime.now();

  final pool = MySQLConnectionPool(
    host: settings['databaseAddress'],
    port: int.parse(settings['databasePort']),
    userName: settings['databaseUsername'],
    password: settings['databasePassword'],
    databaseName: settings['databaseName'],
    maxConnections: 5, // 根据需要调整最大连接数
  );

  // 链接MySQL
  try {
    //await pool.connect();
  } catch (e) {
    print('无法连接到数据库: $e');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('数据库连接错误'),
        content: Text('$e'),
        actions: <Widget>[
          TextButton(
            child: Text('确定'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
    return;
  }

  // 定义文件列表
  final fileList = <String>[];

 // 递归遍历文件夹
  try {
    await _traverseDirectory(folderPath, pool, fileList, name, platformId);

    // 处理文件列表中的文件
    for (final filePath in fileList) {
      await uploadL1B(filePath, pool, showName, name, platformId); // 修改: 使用连接池
    }
  } catch (e) {
    print('处理文件时发生错误: $e');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('文件处理错误'),
        content: Text('$e'),
        actions: <Widget>[
          TextButton(
            child: Text('确定'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  } finally {
    // 关闭连接池
    await pool.close();
  }


  // 记录程序结束时间
  final endTime = DateTime.now();

  // 计算并打印程序运行时间
  final runTime = endTime.difference(startTime).inMilliseconds;
  print('所有文件处理完成，程序运行时间：${runTime/1000.0}秒');
}

// 递归遍历文件夹
Future<void> _traverseDirectory(String dirPath, MySQLConnectionPool pool, List<String> fileList, String name, String platformId) async {
  try {
    final dir = Directory(dirPath);
    final files = await dir.list().toList();
    for (final file in files) {
      if (file is Directory) {
        await _traverseDirectory(file.path, pool, fileList, name, platformId);
      } else if (file.path.toLowerCase().endsWith('.txt')) {
        final filePath = file.path;
        final isDuplicate = await _isDuplicateRecord(pool, filePath, name, platformId);
        if (!isDuplicate) {
          fileList.add(filePath);
        }
      }
    }
  } catch (e) {
    print('遍历文件夹时发生错误: $e');
  }
}

// 检查是否重复记录
Future<bool> _isDuplicateRecord(MySQLConnectionPool pool, String filePath,
    String name, String platformId) async {
  final fileName = path.basename(filePath); // 使用path.basename获取文件名
  final dateTimeStr = fileName.split('_')[5];
  final dt = DateTime.parse(
      '${dateTimeStr.substring(0, 4)}-${dateTimeStr.substring(4, 6)}-${dateTimeStr.substring(6, 8)} ${dateTimeStr.substring(8, 10)}:${dateTimeStr.substring(10, 12)}:${dateTimeStr.substring(12)}');
  final dtStr = dt.toIso8601String();

  final MSTStr = fileName.split('_')[5];
  final MST = MSTStr == 'M' ? 0 : 1;

  final checkSql = '''
  SELECT EXISTS(
    SELECT 1 
    FROM smos_radar_qzgcz_device2 
    WHERE Time = ? 
      AND name = ? 
      AND MST = ? 
      AND Platform_id = ?
  )
''';
 final conn = await pool.getConnection(); // 获取连接
try {
  final checkResult = await conn.execute(checkSql, [dtStr, name, MST, platformId]);
  final exists = checkResult.first[0] == 1;
  return exists;
} catch (e) {
  print('查询过程中发生错误: $e');
  return false;
} finally {
  await conn.close(); // 显式关闭连接
}
}