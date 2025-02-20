import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;
import 'upload_Para.dart';
import 'package:flutter/material.dart';
import 'upload_L1B.dart';
import 'upload_L2.dart';
import 'dart:isolate'; // 添加dart:isolate库以使用Isolate
import 'package:mutex/mutex.dart';

// 新增: 定义日志文件路径
final logFilePath = 'process_log.txt';

// 新增: 定义互斥锁
final _logFileMutex = Mutex();

// 新增: 定义日志记录函数
void logInfo(String message) async {
  await _logFileMutex.acquire();
  try {
    final logContent = '\n[${DateTime.now().toIso8601String()}] INFO: $message';
    await File(logFilePath).writeAsString(logContent, mode: FileMode.append);
  } finally {
    _logFileMutex.release();
  }
}

void logWarning(String message) async {
  await _logFileMutex.acquire();
  try {
    final logContent =
        '\n[${DateTime.now().toIso8601String()}] WARNING: $message';
    await File(logFilePath).writeAsString(logContent, mode: FileMode.append);
  } finally {
    _logFileMutex.release();
  }
}

void logError(String message, [StackTrace? stackTrace]) async {
  await _logFileMutex.acquire();
  try {
    final logContent =
        '\n[${DateTime.now().toIso8601String()}] ERROR: $message\n${stackTrace ?? ''}';
    await File(logFilePath).writeAsString(logContent, mode: FileMode.append);
  } finally {
    _logFileMutex.release();
  }
}

void logDebug(String message) async {
  if (_globalSettings['enableDebugLogging'] == true) {
    await _logFileMutex.acquire();
    try {
      final logContent =
          '\n[${DateTime.now().toIso8601String()}] DEBUG: $message';
      await File(logFilePath).writeAsString(logContent, mode: FileMode.append);
    } finally {
      _logFileMutex.release();
    }
  }
}

void logFatal(String message, [StackTrace? stackTrace]) async {
  await _logFileMutex.acquire();
  try {
    final logContent =
        '\n[${DateTime.now().toIso8601String()}] FATAL: $message\n${stackTrace ?? ''}';
    await File(logFilePath).writeAsString(logContent, mode: FileMode.append);
  } finally {
    _logFileMutex.release();
  }
}

// 新增: 定义全局变量来存储设置
Map<String, dynamic> _globalSettings = {};

// 修改: 初始化时读取设置
Future<void> _initializeSettings() async {
  try {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    _globalSettings = json.decode(settingsContent);
    logDebug('读取设置文件成功: settings.json');
  } catch (e, stackTrace) {
    logError('读取设置文件失败: settings.json', stackTrace);
    rethrow;
  }
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

Future<void> processFile(
    String filePath,
    String folderPath,
    MySqlConnection conn,
    String showName,
    String name,
    String platformId,
    Map<String, dynamic> settings) async {
  // try {
  logDebug('开始处理文件: $filePath');
  if (filePath.contains('L1B')) {
    logDebug('文件类型: L1B');
    await uploadL1B(filePath, conn, showName, name, platformId, settings);
    final newFilePath1 = getRelativeFilePath(filePath, folderPath, 'L1B');
    final newFileDir1 = path.dirname(newFilePath1);
    await Directory(newFileDir1).create(recursive: true);
    logDebug('创建目录: $newFileDir1');

    final newFilePath2 = getRelativeFilePath(filePath, folderPath, 'L2');
    final newFileDir2 = path.dirname(newFilePath2);
    await Directory(newFileDir2).create(recursive: true);
    logDebug('创建目录: $newFileDir2');

    try {
      logDebug(
          '启动 Python 进程进行优化: ${settings['pythonInterpreterPath']} ${settings['optimizationProgramPath']} $filePath $newFilePath1');
      final result = await Process.run(settings['pythonInterpreterPath'],
          [settings['optimizationProgramPath'], filePath, newFilePath1]);
      if (result.stdout.isNotEmpty) {
        print('stdout: ${result.stdout}');
        logDebug('Python 脚本输出: ${result.stdout}');
      }
      if (result.stderr.isNotEmpty) {
        print('stderr: ${result.stderr}');
        logWarning('Python 脚本错误输出: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      logError('Error running Python script: $e', stackTrace);
    }
    await uploadL1B(newFilePath1, conn, showName, name, platformId, settings);
    logDebug('上传 L1B 文件: $newFilePath1');

    try {
      logDebug(
          '启动 Python 进程进行转换: ${settings['pythonInterpreterPath']} ${settings['conversionProgramPath']} $newFilePath1 $newFilePath2');
      final result = await Process.run(settings['pythonInterpreterPath'],
          [settings['conversionProgramPath'], newFilePath1, newFilePath2]);
      if (result.stdout.isNotEmpty) {
        print('stdout: ${result.stdout}');
        logDebug('Python 脚本输出: ${result.stdout}');
      }
      if (result.stderr.isNotEmpty) {
        print('stderr: ${result.stderr}');
        logWarning('Python 脚本错误输出: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      logError('Error running Python script: $e', stackTrace);
    }
    await uploadL2(newFilePath2, conn, showName, name, platformId,
        settings); // 修改: 传递 settings 参数
    logDebug('上传 L2 文件: $newFilePath2');
    await uploadPara(newFilePath2, conn, showName, name, platformId,
        settings['DeviceTableNme']);
    logDebug('上传参数文件: $newFilePath2');
  } else if (filePath.contains('L2')) {
    await uploadL2(filePath, conn, showName, name, platformId,
        settings); // 修改: 传递 settings 参数
    logDebug('上传 L2 文件: $filePath');
  }
  logDebug('文件处理完成: $filePath');
  // } catch (e, stackTrace) {
  //   logError('文件处理失败: $filePath', stackTrace);
  // }
}

Future<void> processFilesInParallel(
    List<String> fileList,
    String folderPath,
    MySqlConnection conn,
    String showName,
    String name,
    String platformId,
    Map<String, dynamic> settings,
    ValueNotifier<int> progressNotifier,
    int processedFiles) async {
  final int maxIsolates = 2; // 设置最大线程数
  final List<Isolate> isolates = [];
  final List<ReceivePort> receivePorts = [];
  int totalFiles = fileList.length;
  int activeIsolates = 0;

  logInfo('开始多线程处理文件');
  for (final filePath in fileList) {
    if (activeIsolates >= maxIsolates) {
      await receivePorts[0].first; // 等待一个Isolate完成处理
      isolates.removeAt(0).kill(priority: Isolate.immediate); // 杀死完成的Isolate
      receivePorts.removeAt(0); // 移除对应的ReceivePort
      activeIsolates--;
    }

    final receivePort = ReceivePort();
    receivePorts.add(receivePort);

    isolates.add(await Isolate.spawn(
      _processFileIsolate,
      {
        'filePath': filePath,
        'sendPort': receivePort.sendPort,
        'folderPath': folderPath,
        'showName': showName,
        'name': name,
        'platformId': platformId,
        'settings': settings,
      },
    ));
    logDebug('启动 Isolate: $filePath');
    print('启动 Isolate: $filePath');

    activeIsolates++;
  }

  for (final receivePort in receivePorts) {
    await receivePort.first; // 等待每个Isolate完成处理
    processedFiles++;
    progressNotifier.value = (processedFiles * 90 / totalFiles + 10).round();
    //logDebug('Isolate 完成处理: processedFiles=$processedFiles');
  }

  for (final isolate in isolates) {
    isolate.kill(priority: Isolate.immediate); // 杀死Isolate
  }
  logInfo('多线程处理文件完成');
}

void _processFileIsolate(Map<String, dynamic> data) async {
  final filePath = data['filePath'] as String;
  final sendPort = data['sendPort'] as SendPort;
  final folderPath = data['folderPath'] as String;
  final showName = data['showName'] as String;
  final name = data['name'] as String;
  final platformId = data['platformId'] as String;
  final settings = data['settings'] as Map<String, dynamic>;

  MySqlConnection? conn;
  try {
    final dbParams = ConnectionSettings(
      host: settings['databaseAddress'],
      port: int.parse(settings['databasePort']),
      user: settings['databaseUsername'],
      password: settings['databasePassword'],
      db: settings['databaseName'],
    );
    conn = await MySqlConnection.connect(dbParams);
    await conn.query('USE ${settings['databaseName']}');
    logDebug(
        '数据库连接成功: ${settings['databaseAddress']}:${settings['databasePort']}/${settings['databaseName']}');
  } catch (e, stackTrace) {
    logError('无法连接到数据库: $e', stackTrace);
    sendPort.send(null); // 发送完成信号
    return;
  }

  await processFile(filePath, folderPath, conn, showName, name, platformId,
      settings); // 处理单个文件

  await conn.close(); // 关闭数据库连接
  sendPort.send(null); // 发送完成信号
  logDebug(
      '数据库连接关闭: ${settings['databaseAddress']}:${settings['databasePort']}/${settings['databaseName']}');
}

// 遍历文件夹并处理数据
Future<void> processFiles(
    BuildContext context, ValueNotifier<int> progressNotifier) async {
  print("开始处理文件");
  // 修改: 添加 BuildContext 参数
  // 读取设置
  await _initializeSettings(); // 初始化设置
  final showName = _globalSettings['show_name'];
  final name = _globalSettings['name'];
  final platformId = _globalSettings['Platform_id'];
  progressNotifier.value = 0;

  // 定义数据库连接参数
  final dbParams = ConnectionSettings(
    host: _globalSettings['databaseAddress'],
    port: int.parse(_globalSettings['databasePort']),
    user: _globalSettings['databaseUsername'],
    password: _globalSettings['databasePassword'],
    db: _globalSettings['databaseName'],
  );

  // 定义需要读取的文件夹路径
  final folderPath = _globalSettings['sourceDataPath'];

  // 记录程序开始时间
  final startTime = DateTime.now();

  // 链接MySQL
  MySqlConnection? conn;
  try {
    if (conn != null) {
      await conn!.close();
    }
    conn = await MySqlConnection.connect(dbParams);
    //print(settings['databaseName']);
    await conn.query('USE ${_globalSettings['databaseName']}');
    logDebug(
        '数据库连接成功: ${_globalSettings['databaseAddress']}:${_globalSettings['databasePort']}/${_globalSettings['databaseName']}');
  } catch (e, stackTrace) {
    logError('无法连接到数据库: $e', stackTrace);
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
  int processedFiles = 0;

  //print(fileList);

  // 使用多线程处理文件列表
  await processFilesInParallel(fileList, folderPath, conn, showName, name,
      platformId, _globalSettings, progressNotifier, processedFiles);

  // 关闭游标和连接
  await conn.close();
  logDebug(
      '数据库连接关闭: ${_globalSettings['databaseAddress']}:${_globalSettings['databasePort']}/${_globalSettings['databaseName']}');

  // 记录程序结束时间
  final endTime = DateTime.now();

  // 计算并打印程序运行时间
  final runTime = endTime.difference(startTime).inMilliseconds;
  print('所有文件处理完成，程序运行时间：${runTime / 1000.0}秒');

  // 新增: 记录日志信息
  final logContent = '''
${startTime.toIso8601String()} 处理文件总数: ${fileList.length} 程序运行时间: ${runTime / 1000.0}秒
处理文件列表: ${fileList.join(', ')}
  ''';

  // 新增: 将日志信息写入文件
  final logFile = File(logFilePath);
  // await logFile.writeAsString(logContent, mode: FileMode.append);
  logInfo('所有文件处理完成，程序运行时间: ${runTime / 1000.0}秒 处理文件总数: ${fileList.length}');

  progressNotifier.value = 0;
}

// 递归遍历文件夹
Future<void> _traverseDirectory(String dirPath, MySqlConnection conn,
    List<String> fileList, String name, String platformId) async {
  try {
    logInfo('开始遍历目录: $dirPath');
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
          logDebug('添加文件到处理列表: $filePath');
        }
      }
    }
    logDebug('目录遍历完成: $dirPath');
  } catch (e, stackTrace) {
    logError('目录遍历失败: $dirPath', stackTrace);
  }
}

// 检查是否重复记录
Future<bool> _isDuplicateRecord(MySqlConnection conn, String filePath,
    String name, String platformId) async {
  try {
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
    //logDebug('执行数据库查询: ${checkSql} 参数: [$dtStr, $name, $MST, $platformId]');
    final checkResult =
        await conn.query(checkSql, [dtStr, name, MST, platformId]);
    final exists = checkResult.first[0] == 1; // 确保返回值是布尔类型
    //print('$fileName 是否重复:$exists');
    logDebug('$fileName 是否重复:$exists');
    //return exists; // 显式转换为 bool
    return false;
  } catch (e, stackTrace) {
    final fileName = path.basename(filePath);
    logError('$fileName 查重过程中发生错误:$e', stackTrace);
    return false;
  }
}
