import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path; // 添加路径处理库
import 'dart:convert'; // 添加json处理库
import 'upload_Para.dart'; // 导入 upload_Para.dart 文件

class TransferPage extends StatelessWidget {
  // 读取 setting.json 文件
  Future<Map<String, dynamic>> _readSettings() async {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    return json.decode(settingsContent);
  }

  // 遍历文件夹并处理数据
  void processFiles() async {
    // 读取设置
    final settings = await _readSettings();
    final showName = settings['show_name'];
    final name = settings['name'];
    final platformId = settings['Platform_id'];

    // 定义数据库连接参数
    final dbParams = ConnectionSettings(
      host: '127.0.0.1',
      port: 3306,
      user: 'root',
      password: 'mysecretpw',
      db: 'joyaiot_monitor',
    );

    // 定义需要读取的文件夹路径
    final folderPath = '/Users/zyqyq/Program/数据集/L2BP/202408';

    // 记录程序开始时间
    final startTime = DateTime.now();

    // 链接MySQL
    final conn = await MySqlConnection.connect(dbParams);

    // 遍历文件夹
    final files = await Directory(folderPath).list().toList();
    for (final file in files) {
      if (file is Directory) {
        final subFiles = await file.list().toList();
        for (final subFile in subFiles) {
          if (subFile.path.endsWith('.TXT')) {
            final filePath = subFile.path;
            // 检查是否重复
            final isDuplicate =
                await _isDuplicateRecord(conn, filePath, name, platformId);
            if (isDuplicate) {
              print('记录已存在，跳过文件: $filePath');
              continue;
            }
            final data =
                await readAndProcessFile(filePath, showName, name, platformId);
            await insertDataToDatabase(conn, data);
          }
        }
      }
    }

    // 关闭游标和连接
    await conn.close();

    // 记录程序结束时间
    final endTime = DateTime.now();

    // 计算并打印程序运行时间
    final runTime = endTime.difference(startTime).inSeconds;
    print('所有文件处理完成，程序运行时间：$runTime秒');
  }

  // 检查是否重复记录
  Future<bool> _isDuplicateRecord(MySqlConnection conn, String filePath,
      String name, String platformId) async {
    final fileName = path.basename(filePath); // 使用path.basename获取文件名
    final dateTimeStr = fileName.split('_')[5];
    final dt = DateTime.parse(
        '${dateTimeStr.substring(0, 4)}-${dateTimeStr.substring(4, 6)}-${dateTimeStr.substring(6, 8)} ${dateTimeStr.substring(8, 10)}:${dateTimeStr.substring(10, 12)}:${dateTimeStr.substring(12)}');
    final dtStr = dt.toIso8601String();

    final MSTStr = fileName.split('_')[5];
    final MST = MSTStr == 'M' ? 0 : 1;

    final checkSql = '''
      SELECT COUNT(*) 
      FROM smos_radar_qzgcz_device2 
      WHERE Time = ? 
        AND name = ? 
        AND MST = ? 
        AND Platform_id = ?
    ''';
    final checkResult = await conn.query(checkSql, [
      dtStr,
      name,
      MST,
      platformId,
    ]);

    // 检查是否存在相同的记录
    final count = checkResult.first[0] as int? ?? 0; // 确保不会出现 null
    return count > 0;
  }


  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: processFiles,
        child: Text('传输页面'),
      ),
    );
  }
}