import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;
import 'upload_Para.dart';
import 'package:flutter/material.dart';
import 'upload_L1B.dart';
import 'upload_L2.dart';
import 'dart:isolate';
import 'package:mutex/mutex.dart';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

// 定义全局变量来存储设置
Map<String, dynamic> _globalSettings = {};
final logger = Logger();

// 定义全局变量来存储 WebSocket 端口
int _webSocketPort = 8765;

// 初始化:读取设置并启动 Python WebSocket 服务端
Future<Process?> _initialize() async {
  // 启动 Python WebSocket 服务端
  Future<Process?> _startPythonWebSocketServer() async {
    try {
      logger.debug('尝试启动 Python WebSocket 服务端: web-server.py');
      final pythonInterpreterPath = _globalSettings['pythonInterpreterPath'];
      final serverScriptPath = 'lib/web-server.py';

      // 动态选择端口
      int port = 8765;
      while (await isPortOpen('localhost', port)) {
        port++;
      }
      _webSocketPort = port;

      // 启动 Python 进程
     final process = await Process.start(
      pythonInterpreterPath, [serverScriptPath, '--port', port.toString()]);

      logger.info('Python WebSocket 服务端已启动，端口: $port');
      print('Python WebSocket 服务端已启动，端口: $port');
      return process; // 返回启动的 Python 进程
    } catch (e, stackTrace) {
      logger.error('启动 Python WebSocket 服务端失败', stackTrace);
      print('启动 Python WebSocket 服务端失败: $stackTrace');
      return null; // 返回 null 表示启动失败
    }
  }

  try {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    _globalSettings = json.decode(settingsContent);
    logger.debug('读取设置文件成功: settings.json');
    return await _startPythonWebSocketServer(); // 返回 Python 进程
  } catch (e, stackTrace) {
    logger.error('初始化设置失败', stackTrace);
    print("初始化设置失败:$stackTrace");
    return null; // 返回 null 表示初始化失败
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

//具体处理逻辑
Future<void> processFile(
    String filePath,
    String folderPath,
    MySqlConnection conn,
    String showName,
    String name,
    String platformId,
    Map<String, dynamic> settings,
    Logger logger,
    WebSocketChannel webSocketChannel,
    Stream<dynamic> stream) async {
  // 新增: 接收 WebSocket 连接
  final fileName = path.basename(filePath);
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
      logger.debug('通过 WebSocket 启动优化任务');
      final optimizeTaskId = Uuid().v4();
      webSocketChannel.sink.add(json.encode({
        "task_type": "optimize",
        "source_file": filePath,
        "output_file": newFilePath1,
        "task_id": optimizeTaskId,
      }));

      await _waitForTaskResponse(stream, optimizeTaskId, "优化", logger);
    } catch (e, stackTrace) {
      logger.error('WebSocket 通信失败: $e', stackTrace);
    }

    await uploadL1B(newFilePath1, conn, showName, name, platformId, settings);
    logger.debug('上传 L1B 文件: $newFilePath1');

    // 使用 WebSocket 进行转换
    try {
      logger.debug('通过 WebSocket 启动转换任务');
      final convertTaskId = Uuid().v4();
      webSocketChannel.sink.add(json.encode({
        "task_type": "convert",
        "source_file": newFilePath1,
        "output_file": newFilePath2,
        "task_id": convertTaskId,
      }));

      await _waitForTaskResponse(stream, convertTaskId, "转换", logger);
    } catch (e, stackTrace) {
      logger.error('WebSocket 通信失败: $e', stackTrace);
      print('WebSocket 通信失败: $e');
    }

    await uploadL2(newFilePath2, conn, showName, name, platformId, settings);
    logger.debug('上传 L2 文件: $newFilePath2');
    await uploadPara(newFilePath2, conn, showName, name, platformId,
        settings['DeviceTableName']);
    logger.debug('上传参数文件: $newFilePath2');
  } else if (filePath.contains('L2')) {
    logger.debug('文件类型: L2');
    await uploadL2(filePath, conn, showName, name, platformId, settings);
    logger.debug('上传 L2 文件: $fileName');
  }
  print('文件处理完成: $fileName');
}

Future<void> _waitForTaskResponse(
  Stream<dynamic> stream,
  String expectedTaskId,
  String taskName,
  Logger logger,
) async {
  try {
    await for (final message in stream) {
      final response = json.decode(message);
      if (response['task_id'] != expectedTaskId) continue;

      if (response.containsKey('error')) {
        logger.error('${taskName}任务失败: ${response['error']}');
        throw Exception('${taskName}任务失败: ${response['error']}');
      } else {
        logger.debug('${taskName}任务完成: ${response['result']}');
        return;
      }
    }
  } catch (e, stackTrace) {
    logger.error('WebSocket 通信失败: $e', stackTrace);
    rethrow;
  }
}

//多线程启动与管理
Future<void> processFilesInParallel(
  List<String> fileList,
  String folderPath,
  String showName,
  String name,
  String platformId,
  Map<String, dynamic> settings,
  ValueNotifier<int> progressNotifier,
  ValueNotifier<int> processedFilesNotifier,
) async {
  final int maxIsolates = Platform.numberOfProcessors;
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
      ((processedFilesNotifier.value * 99 ~/ totalFiles) + 1).round();

  if (ref < fileList.length) {
    workerPort.send(fileList[ref]);
  } else if (processedFilesNotifier.value == totalFiles) {
    exitPort.send(true);
    workerPort.send("END");
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

//单线程管理
void _processFileIsolate(_IsolateParams params) async {
  final ReceivePort taskPort = ReceivePort();
  params.initPort.send(taskPort.sendPort);

  MySqlConnection? conn;
  final logger = Logger(isDebug: params.settings["enableDebugLogging"]);
  WebSocketChannel? webSocketChannel; // 新增: WebSocket 长连接
  Stream<dynamic> broadcastStream;

  try {
    conn = await MySqlConnection.connect(ConnectionSettings(
      host: params.settings['databaseAddress'],
      port: int.parse(params.settings['databasePort']),
      user: params.settings['databaseUsername'],
      password: params.settings['databasePassword'],
      db: params.settings['databaseName'],
    )).timeout(Duration(seconds: 5));
    // 测试连接有效性

    await conn.query('SELECT 1');
    print('数据库连接验证成功');
    // 初始化 WebSocket 连接
    try {
      logger.debug('尝试连接到 WebSocket 服务端');
      webSocketChannel =
          WebSocketChannel.connect(Uri.parse('ws://localhost:$_webSocketPort'));
      broadcastStream = webSocketChannel.stream.asBroadcastStream();
      logger.info('WebSocket 连接成功');
    } catch (e, stackTrace) {
      logger.error('WebSocket 连接失败: $e', stackTrace);
      rethrow;
    }
  } catch (e) {
    logger.error('数据库连接失败: $e');
    logger.flushLogs(params.mainPort);
    return;
  }
  try {
    await conn!.query('SELECT 1');
  } catch (e) {
    // 捕获异常并打印错误信息
    print('数据库连接测试失败1: $e');
    rethrow; // 如果需要继续抛出异常，可以使用 rethrow
  }

  taskPort.listen((filePath) async {
    if (filePath == "END") {
      // 清理资源
      await conn?.close();
      webSocketChannel?.sink.close(); // 关闭 WebSocket 连接

      logger.debug('数据库连接和 WebSocket 连接已关闭');
      logger.flushLogs(params.mainPort);
      return;
    }
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
        webSocketChannel!, // 传递 WebSocket 连接
        broadcastStream,
      );

      params.mainPort.send({
        'type': 'taskCompleted',
        'workerPort': taskPort.sendPort,
      });
      logger.debug('文件处理完成: $filePath');
      logger.flushLogs(params.mainPort);
    } catch (e) {
      logger.error('文件处理失败: $filePath');
      logger.flushLogs(params.mainPort);
    }
  });
}

// 主函数
Future<void> processFiles(
    BuildContext context, ValueNotifier<int> progressNotifier) async {
  print("开始处理文件");

  Process? pythonProcess = await _initialize();

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

  //连接状态检查
  MySqlConnection? conn;
  try {
    conn =
        await MySqlConnection.connect(dbParams).timeout(Duration(seconds: 10));
    await conn.query('SELECT 1');
    //await conn.query('USE `${_globalSettings['databaseName']}`');
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

  //await conn.close();
  final folderPath = _globalSettings['sourceDataPath'];
  final startTime = DateTime.now();

  // 递归遍历文件夹，列表存储在fileList
  final fileList = <String>[];
  await _traverseDirectory(folderPath, conn, fileList, name, platformId,
      _globalSettings['DeviceTableName']);
  progressNotifier.value = 1;

  final processedFilesNotifier = ValueNotifier(0);

  try {
    var isPortAvailable = false;
      while (!isPortAvailable) {
        isPortAvailable = await isPortOpen('localhost', _webSocketPort);
        await Future.delayed(Duration(milliseconds: 100));
      }
    await processFilesInParallel(fileList, folderPath, showName, name,
        platformId, _globalSettings, progressNotifier, processedFilesNotifier);
  } finally {
    if (pythonProcess != null) {
      pythonProcess!.kill(); // 关闭 Python 进程
    }
  }

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

// 递归遍历文件夹，列表存储在fileList
Future<void> _traverseDirectory(
    String dirPath,
    MySqlConnection conn,
    List<String> fileList,
    String name,
    String platformId,
    String DeviceTableName) async {
  // 检查是否重复记录
  Future<bool> _isDuplicateRecord(MySqlConnection conn, String filePath,
      String name, String platformId, String DeviceTableName) async {
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

  try {
    logger.info('开始遍历目录: $dirPath');
    final dir = Directory(dirPath);
    final files = await dir.list().toList();

    for (final file in files) {
      if (file is Directory) {
        await _traverseDirectory(
            file.path, conn, fileList, name, platformId, DeviceTableName);
      } else if (file.path.endsWith('.txt') || file.path.endsWith('.TXT')) {
        final filePath = file.path;
        // 检查是否重复
        final isDuplicate = await _isDuplicateRecord(
            conn, filePath, name, platformId, DeviceTableName);
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

// Logger 类，完成日志相关功能
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


Future<bool> isPortOpen(String host, int port,
      {Duration timeout = const Duration(seconds: 1)}) async {
    try {
      var socket = await Socket.connect(host, port, timeout: timeout);
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }