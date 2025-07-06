import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;
import 'upload_Para.dart';
import 'package:flutter/material.dart';
import 'upload_L1B.dart';
import 'upload_L2.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

// 定义全局变量来存储设置
Map<String, dynamic> _Settings = {};
final logger = Logger();

// 定义全局变量来存储 WebSocket 端口
int _webSocketPort = 8765;

// 初始化:读取设置并启动 Python WebSocket 服务端
Future<Process?> _initialize() async {
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

  // 启动 Python WebSocket 服务端
  Future<Process?> _startPythonWebSocketServer() async {
    try {
      logger.debug('尝试启动 Python WebSocket 服务端: web-server.py');
      final pythonInterpreterPath = _Settings['pythonInterpreterPath'];
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
    _Settings = json.decode(settingsContent);
    _Settings['dbParams'] = ConnectionSettings(
      host: _Settings['databaseAddress'],
      port: int.parse(_Settings['databasePort']),
      user: _Settings['databaseUsername'],
      password: _Settings['databasePassword'],
      db: _Settings['databaseName'],
    );
    logger.debug('读取设置文件成功: settings.json');
    return await _startPythonWebSocketServer(); // 返回 Python 进程
  } catch (e, stackTrace) {
    logger.error('初始化设置失败', stackTrace);
    print("初始化设置失败:$stackTrace");
    return null; // 返回 null 表示初始化失败
  }
}

// 根据filePath和folderPath的相对位置，输出tmp/mid（mid是参数）下相同相对位置的的文件路径
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
    MySqlConnection conn,
    Map<String, dynamic> settings,
    Logger logger,
    WebSocketChannel webSocketChannel,
    Stream<dynamic> stream) async {
  // 新增: 接收 WebSocket 连接
  final folderPath = settings['sourceDataPath'];
  final fileName = path.basename(filePath);
  logger.debug('开始处理文件: $fileName');

  if (fileName.contains('L1B')) {
    logger.debug('文件类型: L1B');
    await uploadL1B(filePath, conn, settings);
    final newFilePath1 = getRelativeFilePath(filePath, folderPath, 'L1B');
    final newFileDir1 = path.dirname(newFilePath1);
    await Directory(newFileDir1).create(recursive: true);
    logger.debug('创建目录: $newFileDir1');

    final newFilePath2 = getRelativeFilePath(filePath, folderPath, 'L2');
    final newFileDir2 = path.dirname(newFilePath2);
    await Directory(newFileDir2).create(recursive: true);
    logger.debug('创建目录: $newFileDir2');

    try {
      //logger.debug('通过 WebSocket 启动优化任务');
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

    await uploadL1B(newFilePath1, conn, settings);
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

    await uploadL2(newFilePath2, conn, settings);
    logger.debug('上传 L2 文件: $newFilePath2');
    await uploadPara(newFilePath2, conn, settings);
    logger.debug('上传参数文件: $newFilePath2');
  } else if (fileName.contains('L2')) {
    logger.debug('文件类型: L2');
    await uploadL2(filePath, conn, settings);
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

// Logger 类，完成日志相关功能
class Logger {
  List<String> _logCache = [];
  bool _isDebug = true; // 默认为 true

  Logger({bool? isDebug}) {
    _isDebug = isDebug ?? _Settings['enableDebugLogging'] ?? true;
  }
  // 基本日志写入函数
  void _log(String level, String message, [StackTrace? stackTrace]) {
    final logEntry =
        '\n[${DateTime.now().toIso8601String()}] $level: $message${stackTrace != null ? '\n$stackTrace' : ''}';
    _logCache.add(logEntry);
  }

  void info(String message) => _log('INFO', message);
  void warning(String message) => _log('WARNING', message);
  void error(String message, [StackTrace? stackTrace]) =>
      _log('ERROR', message, stackTrace);
  void debug(String message) {
    if (_Settings['enableDebugLogging'] != null) {
      if (_Settings['enableDebugLogging'] == true) {
        _log('DEBUG', message);
      }
    } else if (_isDebug) {
      _log('DEBUG', message);
    }
  }

  void fatal(String message, [StackTrace? stackTrace]) =>
      _log('FATAL', message, stackTrace);

  void writeLogsToFile() async {
    final file = File('process_log.txt');
    final logsToWrite = _logCache.toList();
    _logCache.clear();
    final sink = file.openWrite(mode: FileMode.append);
    for (final logEntry in logsToWrite) {
      sink.write(logEntry);
    }
    await sink.close();
  }
}

// 主函数（单线程处理文件）
Future<void> processFiles(
    BuildContext context, ValueNotifier<int> progressNotifier) async {
  print("开始处理文件");
  Process? pythonProcess = await _initialize();
  progressNotifier.value = 0;
  MySqlConnection? conn =
      await checkDatabaseConnection(context, _Settings['dbParams']);
  final startTime = DateTime.now();
  final fileList = <String>[];
  await _traverseDirectory(
      _Settings['sourceDataPath'],
      conn,
      fileList,
      _Settings['name'],
      _Settings['Platform_id'],
      _Settings['DeviceTableName']);
  progressNotifier.value = 1;

  // 单线程顺序处理文件
  int processed = 0;
  for (final filePath in fileList) {
    try {
      await processFile(
        filePath,
        conn!,
        _Settings,
        logger,
        WebSocketChannel.connect(Uri.parse('ws://localhost:$_webSocketPort')),
        const Stream.empty(), // 这里可根据实际情况传递正确的 stream
      );
      processed++;
      progressNotifier.value =
          ((processed * 95 ~/ fileList.length) + 5).round();
    } catch (e) {
      logger.error('文件处理失败: $filePath');
      print("文件处理失败: $filePath $e");
    }
  }

  try {
    await conn?.close();
  } catch (_) {}
  logger.debug('数据库连接关闭');
  final endTime = DateTime.now();
  final runTime = endTime.difference(startTime).inMilliseconds;
  print('所有文件处理完成，程序运行时间: ${runTime / 1000.0}秒 处理文件总数: ${fileList.length}');
  logger.info(
      '所有文件处理完成，程序运行时间: ${runTime / 1000.0}秒 处理文件总数: ${fileList.length}');
  progressNotifier.value = 0;
  logger.writeLogsToFile();
  if (pythonProcess != null) {
    Future.delayed(Duration(seconds: 5), () {
      print("Python  进程已关闭");
      pythonProcess.kill();
    });
  }
}

// 递归遍历文件夹，列表存储在fileList
Future<void> _traverseDirectory(
    String dirPath,
    MySqlConnection? conn,
    List<String> fileList,
    String name,
    String platformId,
    String DeviceTableName) async {
  // 检查是否重复记录
  Future<bool> _isDuplicateRecord(MySqlConnection? conn, String filePath,
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
          await conn?.query(checkSql, [dtStr, name, MST, platformId]);
      final exists = checkResult!.first[0] == 1; // 确保返回值是布尔类型
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
          //logger.debug('添加文件到处理列表: $filePath');
        }
      }
    }
    logger.debug('目录遍历完成: $dirPath');
  } catch (e, stackTrace) {
    logger.error('目录遍历失败: $dirPath', stackTrace);
  }
}

// 新增数据库连接检查函数
Future<MySqlConnection?> checkDatabaseConnection(
    BuildContext context, ConnectionSettings dbParams) async {
  MySqlConnection? conn;
  try {
    conn =
        await MySqlConnection.connect(dbParams).timeout(Duration(seconds: 10));
    await conn.query('SELECT 1');
    logger.debug('数据库连接成功');
    return conn;
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
    return null;
  }
}
