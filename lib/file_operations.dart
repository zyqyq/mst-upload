import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;
import 'upload_Para.dart';
import 'package:flutter/material.dart';
import 'upload_L1B.dart';
import 'upload_L2.dart';
import 'dart:io';

// 定义 _readSettings 方法
Future<Map<String, dynamic>> _readSettings() async {
  final settingsFile = File('settings.json');
  final settingsContent = await settingsFile.readAsString();
  return json.decode(settingsContent);
}

// 新增: 根据filePath和folderPath的相对位置，输出tmp/mid（mid是参数）下相同相对位置的的文件路径
String getRelativeFilePath(String filePath, String folderPath, String mid) {
  final relativePath = path.relative(filePath, from: folderPath);
  final fileExtension = path.extension(relativePath);
  final fileNameWithoutExtension = path.basenameWithoutExtension(relativePath);
  final newFileName = '$fileNameWithoutExtension${"_processed"}$fileExtension';
  String resultPath = path.join('tmp', mid, newFileName);

  if (mid == 'L2') {
    resultPath = resultPath.replaceFirst('PSPP_L1B', 'AWCN_L2');
  }

  return resultPath;
}

// 遍历文件夹并处理数据
Future<void> processFiles(
    BuildContext context, ValueNotifier<int> progressNotifier) async {
  print("开始处理文件");
  // 修改: 添加 BuildContext 参数
  // 读取设置
  final settings = await _readSettings();
  final showName = settings['show_name'];
  final name = settings['name'];
  final platformId = settings['Platform_id'];
  progressNotifier.value = 0;

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

  // 链接MySQL
  MySqlConnection? conn;
  try {
    if (conn != null) {
      await conn!.close();
    }
    conn = await MySqlConnection.connect(dbParams);
    print(settings['databaseName']);
    await conn.query('USE ${settings['databaseName']}');
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
  await _traverseDirectory(folderPath, conn, fileList, name, platformId);
  progressNotifier.value = 10;
  // 更新总文件数
  int totalFiles = fileList.length;
  int processedFiles = 0;

  //print(fileList);

  // 处理文件列表中的文件
  for (final filePath in fileList) {
    print(filePath);
    if (filePath.contains('L1B')) {
      await uploadL1B(filePath, conn, showName, name, platformId, settings);
      final newFilePath1 = getRelativeFilePath(filePath, folderPath, 'L1B');
      final newFileDir1 = path.dirname(newFilePath1);
      await Directory(newFileDir1).create(recursive: true);

      final newFilePath2 = getRelativeFilePath(filePath, folderPath, 'L2');
      print(newFilePath2);
      final newFileDir2 = path.dirname(newFilePath2);
      await Directory(newFileDir2).create(recursive: true);

      try {
        // 启动 Python 进程并传递参数
        final result = await Process.run(
            settings['pythonInterpreterPath'],
            [settings['optimizationProgramPath'], filePath, newFilePath1]);
        // 打印脚本的输出
        if (result.stdout.isNotEmpty) {
          print('stdout: ${result.stdout}');
        }
        if (result.stderr.isNotEmpty) {
          print('stderr: ${result.stderr}');
        }
      } catch (e) {
        // 处理异常
        print('Error running Python script: $e');
      }
      await uploadL1B(newFilePath1, conn, showName, name, platformId, settings);

      try {
        // 启动 Python 进程并传递参数
        final result = await Process.run(
            settings['pythonInterpreterPath'],
            [settings['conversionProgramPath'], newFilePath1, newFilePath2]);
        // 打印脚本的输出
        if (result.stdout.isNotEmpty) {
          print('stdout: ${result.stdout}');
        }
        if (result.stderr.isNotEmpty) {
          print('stderr: ${result.stderr}');
        }
      } catch (e) {
        // 处理异常
        print('Error running Python script: $e');
      }
      await uploadL2(newFilePath2, conn, showName, name, platformId,
          settings); // 修改: 传递 settings 参数
      await uploadPara(newFilePath2, conn, showName, name, platformId,
          settings['DeviceTableNme']);
    } else if (filePath.contains('L2')) {
      await uploadL2(filePath, conn, showName, name, platformId,
          settings); // 修改: 传递 settings 参数
    }
    // 更新进度
    processedFiles++;
    progressNotifier.value = (processedFiles * 90 / totalFiles+10).round();
  }

  // 关闭游标和连接
  await conn.close();

  // 记录程序结束时间
  final endTime = DateTime.now();

  // 计算并打印程序运行时间
  final runTime = endTime.difference(startTime).inMilliseconds;
  print('所有文件处理完成，程序运行时间：${runTime / 1000.0}秒');

  progressNotifier.value = 0;
}

// 递归遍历文件夹
Future<void> _traverseDirectory(String dirPath, MySqlConnection conn,
    List<String> fileList, String name, String platformId) async {
  final dir = Directory(dirPath);
  final files = await dir.list().toList();
  for (final file in files) {
    if (file is Directory) {
      await _traverseDirectory(file.path, conn, fileList, name, platformId);
    } else if (file.path.endsWith('.txt') || file.path.endsWith('.TXT')) {
      final filePath = file.path;
      // 检查是否重复
      final isDuplicate =
          await _isDuplicateRecord(conn, filePath, name, platformId);
      if (!isDuplicate) {
        fileList.add(filePath);
      }
    }
  }
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
  SELECT EXISTS(
    SELECT 1 
    FROM smos_radar_qzgcz_device2 
    WHERE Time = ? 
      AND name = ? 
      AND MST = ? 
      AND Platform_id = ?
  )
''';
  try {
    final checkResult =
        await conn.query(checkSql, [dtStr, name, MST, platformId]);
    final exists = checkResult.first[0] == 1; // 确保返回值是布尔类型
    print('$fileName 是否重复:$exists');
    return exists; // 显式转换为 bool
  } catch (e) {
    print('$fileName查询过程中发生错误:$e');
    return false; // 或者根据具体需求处理异常
  }
}
