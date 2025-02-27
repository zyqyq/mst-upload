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
import 'dart:async';

// 新增: 定义全局变量来存储设置
Map<String, dynamic> _globalSettings = {};
final logger = Logger();

// 修改: 初始化时读取设置
Future<void> _initializeSettings() async {
  try {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    _globalSettings = json.decode(settingsContent);
    logger.debug('读取设置文件成功: settings.json');
  } catch (e, stackTrace) {
    logger.error('读取设置文件失败: settings.json', stackTrace);
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
    Map<String, dynamic> settings,
    Logger logger) async {
  final fileName = path.basename(filePath);
  //print('开始处理文件: $fileName');
  // try {
  logger.debug('开始处理文件: $fileName');
  if (fileName.contains('L1B')) {
    logger.debug('文件类型: L1B');

    await uploadL1B(filePath, conn, showName, name, platformId, settings);
    final newFilePath1 = getRelativeFilePath(filePath, folderPath, 'L1B');
    final newFileDir1 = path.dirname(newFilePath1);
    await Directory(newFileDir1).create(recursive: true);
    logger.debug('创建目录: $newFileDir1');

    final newFilePath2 = getRelativeFilePath(filePath, folderPath, 'L2');
    final newFileDir2 = path.dirname(newFilePath2);
    await Directory(newFileDir2).create(recursive: true);
    logger.debug('创建目录: $newFileDir2');

    try {
      logger.debug(
          '启动 Python 进程进行优化: ${settings['pythonInterpreterPath']} ${settings['optimizationProgramPath']} $filePath $newFilePath1');
      final result = await Process.run(settings['pythonInterpreterPath'],
          [settings['optimizationProgramPath'], filePath, newFilePath1]);
      if (result.stdout.isNotEmpty) {
        print('stdout: ${result.stdout}');
        logger.debug('处理 $fileName Python 脚本输出: ${result.stdout}');
      }
      if (result.stderr.isNotEmpty) {
        print('stderr: ${result.stderr}');
        logger.warning('优化 $fileName 时Python脚本错误输出: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      logger.error('Error running Python script: $e', stackTrace);
    }
    await uploadL1B(newFilePath1, conn, showName, name, platformId, settings);
    logger.debug('上传 L1B 文件: $newFilePath1');

    try {
      logger.debug(
          '启动 Python 进程进行转换: ${settings['pythonInterpreterPath']} ${settings['conversionProgramPath']} $newFilePath1 $newFilePath2');
      final result = await Process.run(settings['pythonInterpreterPath'],
          [settings['conversionProgramPath'], newFilePath1, newFilePath2]);
      if (result.stdout.isNotEmpty) {
        print('stdout: ${result.stdout}');
        logger.debug('处理 fileName 时Python 脚本输出: ${result.stdout}');
      }
      if (result.stderr.isNotEmpty) {
        print('stderr: ${result.stderr}');
        logger.warning('转换 $fileName 时Python脚本错误输出: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      logger.error('Error running Python script: $e', stackTrace);
    }
    await uploadL2(newFilePath2, conn, showName, name, platformId,
        settings); // 修改: 传递 settings 参数
    logger.debug('上传 L2 文件: $newFilePath2');
    await uploadPara(newFilePath2, conn, showName, name, platformId,
        settings['DeviceTableName']);
    logger.debug('上传参数文件: $newFilePath2');
    //print('上传参数文件: ${settings['DeviceTableName']}');
  } else if (filePath.contains('L2')) {
    logger.debug('文件类型: L2');
    //print('文件类型: L2');
    await uploadL2(filePath, conn, showName, name, platformId,
        settings); // 修改: 传递 settings 参数
    logger.debug('上传 L2 文件: $fileName');
  }
  logger.debug('文件处理完成: $fileName');
  // } catch (e, stackTrace) {
  //   logger.error('文件处理失败: $filePath', stackTrace);
  // }
}

Future<void> processFilesInParallel(
  List<String> fileList,
  String folderPath,
  MySqlConnection connection,
  String showName,
  String name,
  String platformId,
  Map<String, dynamic> settings,
  ValueNotifier<int> progressNotifier,
  ValueNotifier<int> processedFilesNotifier,
) async {
  final int maxIsolates = Platform.numberOfProcessors ~/ 2;
  final List<Isolate> isolates = [];
  final List<SendPort> workerPorts = [];
  int totalFiles = fileList.length;
  int currentFileIndex = 0;

  final ReceivePort mainReceivePort = ReceivePort();
  final ReceivePort exitPort = ReceivePort();

  // 主端口监听逻辑
  mainReceivePort.listen((message) {
    if (message is Map<String, dynamic>) {
      if (message['type'] == 'log') {
        logger.syncState(message['data']);
        logger.writeLogsToFile();
      } else if (message['type'] == 'taskCompleted') {
        _handleTaskCompletion(
          message['workerPort'],
          fileList,
          workerPorts,
          exitPort.sendPort,
          processedFilesNotifier,
          progressNotifier,
          totalFiles,
          ref: currentFileIndex,
        );
        currentFileIndex++;
      }
    }
  });

  // 创建隔离线程
  for (int i = 0; i < maxIsolates; i++) {
    final initPort = ReceivePort();
    isolates.add(await Isolate.spawn(
      _processFileIsolate,
      _IsolateParams(
        initPort.sendPort,
        mainReceivePort.sendPort,
        folderPath,
        showName,
        name,
        platformId,
        settings,
      ),
    ));

    // 获取工作线程通信端口
    final SendPort workerPort = await initPort.first;
    workerPorts.add(workerPort);

    // 分配初始任务
    if (currentFileIndex < totalFiles) {
      workerPort.send(fileList[currentFileIndex++]);
    }
  }

  // 等待所有任务完成
  await exitPort.first;

  // 清理资源
  for (final isolate in isolates) {
    isolate.kill(priority: Isolate.immediate);
  }
  mainReceivePort.close();
  exitPort.close();
}

void _handleTaskCompletion(
  SendPort workerPort,
  List<String> fileList,
  List<SendPort> workerPorts,
  SendPort exitPort,
  ValueNotifier<int> processedFilesNotifier,
  ValueNotifier<int> progressNotifier,
  int totalFiles, {
  required int ref,
}) {
  processedFilesNotifier.value++;
  progressNotifier.value =
      ((processedFilesNotifier.value * 90 ~/ totalFiles) + 10).round();

  if (ref < fileList.length) {
    workerPort.send(fileList[ref]);
  } else if (processedFilesNotifier.value == totalFiles) {
    exitPort.send(true);
  }
}

class _IsolateParams {
  final SendPort initPort;
  final SendPort mainPort;
  final String folderPath;
  final String showName;
  final String name;
  final String platformId;
  final Map<String, dynamic> settings;

  _IsolateParams(
    this.initPort,
    this.mainPort,
    this.folderPath,
    this.showName,
    this.name,
    this.platformId,
    this.settings,
  );
}

void _processFileIsolate(_IsolateParams params) async {
  final ReceivePort taskPort = ReceivePort();
  params.initPort.send(taskPort.sendPort);

  MySqlConnection? conn;
  final logger = Logger(isDebug: params.settings["enableDebugLogging"]);

  try {
    conn = await MySqlConnection.connect(ConnectionSettings(
      host: params.settings['databaseAddress'],
      port: int.parse(params.settings['databasePort']),
      user: params.settings['databaseUsername'],
      password: params.settings['databasePassword'],
      db: params.settings['databaseName'],
    ));
  } catch (e) {
    logger.error('数据库连接失败: $e');
    logger.flushLogs(params.mainPort);
    return;
  }

  taskPort.listen((filePath) async {
    try {
      await processFile(
        filePath,
        params.folderPath,
        conn!,
        params.showName,
        params.name,
        params.platformId,
        params.settings,
        logger,
      );

      params.mainPort.send({
        'type': 'taskCompleted',
        'workerPort': taskPort.sendPort,
      });
      logger.debug('文件处理完成: $filePath');
      print('文件处理完成: $filePath');
      logger.flushLogs(params.mainPort);
    } catch (e) {
      logger.error('文件处理失败: $filePath');
      logger.flushLogs(params.mainPort);
    }
  });
}

// 遍历文件夹并处理数据
Future<void> processFiles(
    BuildContext context, ValueNotifier<int> progressNotifier) async {
  print("开始处理文件");
  await _initializeSettings();
  final showName = _globalSettings['show_name'];
  final name = _globalSettings['name'];
  final platformId = _globalSettings['Platform_id'];
  progressNotifier.value = 0;
  final dbParams = ConnectionSettings(
    host: _globalSettings['databaseAddress'],
    port: int.parse(_globalSettings['databasePort']),
    user: _globalSettings['databaseUsername'],
    password: _globalSettings['databasePassword'],
    db: _globalSettings['databaseName'],
  );

  MySqlConnection? conn;
  try {
    conn = await MySqlConnection.connect(dbParams);
    await conn.query('USE `${_globalSettings['databaseName']}`');
    logger.debug('数据库连接成功');
  } catch (e, stackTrace) {
    logger.error('无法连接到数据库: $e', stackTrace);
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

  final folderPath = _globalSettings['sourceDataPath'];
  final startTime = DateTime.now();

  final fileList = <String>[];
  await _traverseDirectory(folderPath, conn, fileList, name, platformId,
      _globalSettings['DeviceTableName'], progressNotifier);
  progressNotifier.value = 10;

  final processedFilesNotifier = ValueNotifier(0);
  await processFilesInParallel(
      fileList,
      folderPath,
      conn!, // 修改: 传递 MySqlConnection 对象
      showName,
      name,
      platformId,
      _globalSettings,
      progressNotifier,
      processedFilesNotifier);

  try {
    await conn?.close();
  } catch (_) {}
  logger.debug('数据库连接关闭');

  final endTime = DateTime.now();
  final runTime = endTime.difference(startTime).inMilliseconds;
  print('所有文件处理完成，程序运行时间：${runTime / 1000.0}秒');

  logger
      .info('所有文件处理完成，程序运行时间: ${runTime / 1000.0}秒 处理文件总数: ${fileList.length}');

  progressNotifier.value = 0;
  logger.writeLogsToFile();
}

// 递归遍历文件夹
Future<void> _traverseDirectory(
    String dirPath,
    MySqlConnection conn,
    List<String> fileList,
    String name,
    String platformId,
    String DeviceTableName,
    ValueNotifier<int> duplicateCheckProgressNotifier) async {
  try {
    logger.info('开始遍历目录: $dirPath');
    final dir = Directory(dirPath);
    final files = await dir.list().toList();
    int totalFiles = files.length;
    int processedFiles = 0;

    for (final file in files) {
      processedFiles++;
      duplicateCheckProgressNotifier.value =
          (processedFiles * 10 ~/ totalFiles);

      if (file is Directory) {
        await _traverseDirectory(file.path, conn, fileList, name, platformId,
            DeviceTableName, duplicateCheckProgressNotifier);
      } else if (file.path.endsWith('.txt') || file.path.endsWith('.TXT')) {
        final filePath = file.path;
        // 检查是否重复
        final isDuplicate = await _isDuplicateRecord(conn, filePath, name,
            platformId, DeviceTableName, duplicateCheckProgressNotifier);
        if (!isDuplicate) {
          fileList.add(filePath);
          logger.debug('添加文件到处理列表: $filePath');
        }
      }
    }
    logger.debug('目录遍历完成: $dirPath');
  } catch (e, stackTrace) {
    logger.error('目录遍历失败: $dirPath', stackTrace);
  }
}

// 检查是否重复记录
Future<bool> _isDuplicateRecord(
    MySqlConnection conn,
    String filePath,
    String name,
    String platformId,
    String DeviceTableName,
    ValueNotifier<int> duplicateCheckProgressNotifier) async {
  try {
    final fileName = path.basenameWithoutExtension(filePath);
    final parts = fileName.split('_');
    if (parts.length < 6) {
      logger.warning('文件名格式错误: $fileName');
      return true;
    }

    final dateTimeStr = parts[5];
    if (dateTimeStr.length != 14) {
      logger.warning('时间戳格式错误: $dateTimeStr');
      return true;
    }

    final dt = DateTime.tryParse('${dateTimeStr.substring(0, 4)}-'
        '${dateTimeStr.substring(4, 6)}-'
        '${dateTimeStr.substring(6, 8)} '
        '${dateTimeStr.substring(8, 10)}:'
        '${dateTimeStr.substring(10, 12)}:'
        '${dateTimeStr.substring(12)}');

    if (dt == null) {
      logger.warning('无法解析时间戳: $dateTimeStr');
      return true;
    }
    final dtStr = dt.toIso8601String();
    final MSTStr = parts[7];
    final MST = MSTStr == 'M' ? 0 : 1;
    //print(DeviceTableName);
    final checkSql = '''
      SELECT EXISTS(
        SELECT 1 
        FROM `${DeviceTableName}`
        WHERE Time = ? 
          AND name = ? 
          AND MST = ? 
          AND Platform_id = ?
      )
    ''';
    //logger.debug('执行数据库查询: ${checkSql} 参数: [$dtStr, $name, $MSTStr, $platformId]');
    final checkResult =
        await conn.query(checkSql, [dtStr, name, MST, platformId]);
    final exists = checkResult.first[0] == 1; // 确保返回值是布尔类型
    //print('$fileName 是否重复:$exists');
    logger.debug('$fileName 是否重复:$exists');
    //return exists; // 显式转换为 bool
    return false;
  } catch (e, stackTrace) {
    logger.error('查重失败: $e', stackTrace);
    return true;
  }
}

// 新增: Logger 类
class Logger {
  List<String> _logCache = [];
  bool _isDebug = true; // 默认为 true
  final _writeLock = Mutex();

  // 修改构造函数参数名
  Logger({bool? isDebug}) {
    _isDebug = isDebug ?? _globalSettings['enableDebugLogging'] ?? true;
  }
  // 基本日志写入函数
  void _log(String level, String message, [StackTrace? stackTrace]) {
    final logEntry =
        '\n[${DateTime.now().toIso8601String()}] $level: $message${stackTrace != null ? '\n$stackTrace' : ''}';
    _logCache.add(logEntry);
  }

  // 不同级别的日志写入
  void info(String message) => _log('INFO', message);
  void warning(String message) => _log('WARNING', message);
  void error(String message, [StackTrace? stackTrace]) =>
      _log('ERROR', message, stackTrace);
  void debug(String message) {
    if (_globalSettings['enableDebugLogging'] != null) {
      if (_globalSettings['enableDebugLogging'] == true) {
        _log('DEBUG', message);
      }
    } else if (_isDebug) {
      _log('DEBUG', message);
    }
  }

  void fatal(String message, [StackTrace? stackTrace]) =>
      _log('FATAL', message, stackTrace);

  // 新增: 将日志信息发送到主线程
  void flushLogs(SendPort sendPort) {
    if (_logCache.isNotEmpty) {
      sendPort.send({'type': 'log', 'data': _logCache});
      _logCache.clear();
    }
  }

  void syncState(List<String> other) {
    _logCache.addAll(other);
  }

  void writeLogsToFile() async {
  final file = File('process_log.txt');
  
  // 创建副本并原子化清空（关键修复）
  final logsToWrite = _logCache.toList(); 
  _logCache.clear(); // 立即清空原列表
  
  // 使用同步写入避免异步间隙（优化点）
  final sink = file.openWrite(mode: FileMode.append);
  await _writeLock.acquire();
  try {
    for (final logEntry in logsToWrite) {
      sink.write(logEntry); // 同步写入操作
    }
  } finally {
    await sink.close(); // 异步关闭文件流
  }
}
}
