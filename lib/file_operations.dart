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
import 'dart:collection';
import 'dart:async'; 

// 新增: 定义全局变量来存储设置
Map<String, dynamic> _globalSettings = {};
// 新增: 全局 Logger 实例
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
    Map<String, dynamic> settings) async {
  final fileName = path.basename(filePath);
  print('开始处理文件: $fileName');
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
        settings['DeviceTableNme']);
    logger.debug('上传参数文件: $newFilePath2'); 
    //print('上传参数文件: $newFilePath2');
  } else if (filePath.contains('L2')) {
    logger.debug('文件类型: L2'); 
    print('文件类型: L2');
    await uploadL2(filePath, conn, showName, name, platformId,
        settings); // 修改: 传递 settings 参数
    logger.debug('上传 L2 文件: $fileName'); 
  }
  logger.debug('文件处理完成: $fileName'); 
  // } catch (e, stackTrace) {
  //   logger.error('文件处理失败: $filePath', stackTrace); 
  // }
}

// 连接池类改进
class ConnectionPool {
  final List<MySqlConnection> _pool = [];
  final ConnectionSettings _settings;
  final int _maxSize;
  final Mutex _lock = Mutex();
  final Stopwatch _validationTimer = Stopwatch()..start();

  ConnectionPool(this._settings, {int maxSize = 3}) : _maxSize = maxSize;

  Future<MySqlConnection> getConnection() async {
    await _lock.acquire();
    try {
      // 定期全量验证(每5分钟)
      if (_validationTimer.elapsed.inMinutes >= 5) {
        await _validatePool();
        _validationTimer.reset();
      }

      while (_pool.isNotEmpty) {
        final conn = _pool.removeLast();
        if (await _isConnectionValid(conn)) {
          return conn;
        }
      }
      return await MySqlConnection.connect(_settings);
    } finally {
      _lock.release();
    }
  }

  Future<void> _validatePool() async {
    await _lock.acquire();
    try {
      final validConnections = <MySqlConnection>[];
      for (final conn in _pool) {
        if (await _isConnectionValid(conn)) {
          validConnections.add(conn);
        } else {
          await conn.close();
        }
      }
      _pool
        ..clear()
        ..addAll(validConnections);
      logger.debug('连接池验证完成，有效连接数: ${_pool.length}');
    } finally {
      _lock.release();
    }
  }

  Future<bool> _isConnectionValid(MySqlConnection conn) async {
    try {
      await conn.query('SELECT 1, NOW()'); // 增强型心跳检测
      return true;
    } catch (_) {
      await conn.close();
      return false;
    }
  }

  Future<void> releaseConnection(MySqlConnection conn) async {
    await _lock.acquire();
    try {
      if (await _isConnectionValid(conn) && _pool.length < _maxSize) {
        _pool.add(conn);
      } else {
        await conn.close();
      }
    } finally {
      _lock.release();
    }
  }

  // 新增closeAll方法
  Future<void> closeAll() async {
    await _lock.acquire();
    try {
      await logger.ensureLogsFlushed();
      for (final conn in _pool) {
        try {
          await conn.close();
        } catch (_) {}
      }
      _pool.clear();
    } finally {
      _lock.release();
    }
  }
}

// 新增: 定义 _processFileIsolate 函数
void _processFileIsolate(Map<String, dynamic> params) async {
  final filePath = params['filePath'];
  final sendPort = params['sendPort'] as SendPort;
  final folderPath = params['folderPath'];
  final showName = params['showName'];
  final name = params['name'];
  final platformId = params['platformId'];
  final settings = params['settings'];
  final connectionPool = params['connectionPool'] as ConnectionPool;
  final receivePort = ReceivePort();
  receivePort.listen((_) {}); // 保持Isolate存活

  final dbParams = ConnectionSettings(
    host: settings['databaseAddress'],
    port: int.parse(settings['databasePort']),
    user: settings['databaseUsername'],
    password: settings['databasePassword'],
    db: settings['databaseName'],
  );
  //MySqlConnection conn;
  final conn = await connectionPool.getConnection();
  try {
    final conn = await connectionPool.getConnection();
    await conn.query('USE `${settings['databaseName']}`');
    logger.debug('数据库连接成功'); 
  } catch (e, stackTrace) {
    logger.error('无法连接到数据库: $e', stackTrace); 
    sendPort.send(false);
    return;
  }

  //final connectionPool = ConnectionPool(dbParams, maxSize: 5); // 初始化连接池
  try {
    // 确保连接在使用前是有效的
    final conn = await connectionPool.getConnection();
    await processFile(
        filePath, folderPath, conn, showName, name, platformId, settings);
    logger.debug('文件处理完成: $filePath'); 
    sendPort.send(true);
  } catch (e, stackTrace) {
    logger.error('文件处理失败: $filePath', stackTrace); 
    sendPort.send(false);
  } finally {
    await logger.ensureLogsFlushed();  // ⇽-- 新增等待刷盘
    receivePort.close();
    try {
      if (conn != null) {
        await connectionPool.releaseConnection(conn);
      }
    } catch (_) {}
    logger.debug('数据库连接关闭'); 
    //await connectionPool.releaseConnection(conn); // 清理连接池
  }
}

Future<void> processFilesInParallel(
  List<String> fileList,
  String folderPath,
  ConnectionPool connectionPool, // 修改参数类型
  String showName,
  String name,
  String platformId,
  Map<String, dynamic> settings,
  ValueNotifier<int> progressNotifier,
  ValueNotifier<int> processedFilesNotifier,
) async {
  final int maxIsolates = Platform.numberOfProcessors ~/ 2; // 动态调整隔离线程数
  final List<Isolate> isolates = [];
  final List<ReceivePort> receivePorts = [];
  int totalFiles = fileList.length;
  int activeIsolates = 0;

  logger.info('开始多线程处理文件，最大线程数 $maxIsolates'); 
  for (final filePath in fileList) {
    if (activeIsolates >= maxIsolates) {
      await receivePorts[0].first;
      processedFilesNotifier.value++;
      progressNotifier.value =
          ((processedFilesNotifier.value * 90 ~/ totalFiles) + 10).round();
      //print('Processed: ${processedFilesNotifier.value}');
      isolates.removeAt(0).kill(priority: Isolate.immediate);
      receivePorts.removeAt(0);
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
        'connectionPool': connectionPool,
      },
    ));
    logger.debug('启动 Isolate: ${path.basename(filePath)}'); 
    print('启动 Isolate: ${path.basename(filePath)}');

    activeIsolates++;
  }

  // 等待所有 ReceivePort 收到消息
  for (final receivePort in receivePorts) {
    await receivePort.first;
  }

  // 处理全局退出信号
  ProcessSignal.sigint.watch().listen((_) async {
    await logger.ensureLogsFlushed(); 
    exit(0);
  });

  for (final isolate in isolates) {
    isolate.kill(priority: Isolate.immediate);
  }
  logger.info('多线程处理文件完成'); 
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
  final connectionPool =
      ConnectionPool(dbParams, maxSize: Platform.numberOfProcessors * 2);

  final folderPath = _globalSettings['sourceDataPath'];
  final startTime = DateTime.now();

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

  final fileList = <String>[];
  await _traverseDirectory(folderPath, conn, fileList, name, platformId);
  progressNotifier.value = 10;

  //final connectionPool = ConnectionPool(dbParams, maxSize: 5); // 初始化连接池
  final processedFilesNotifier = ValueNotifier(0);
  await processFilesInParallel(
      fileList,
      folderPath,
      connectionPool,
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

  logger.info('所有文件处理完成，程序运行时间: ${runTime / 1000.0}秒 处理文件总数: ${fileList.length}'); 

  progressNotifier.value = 0;

  await connectionPool.closeAll(); // 清理连接池
}

// 递归遍历文件夹
Future<void> _traverseDirectory(String dirPath, MySqlConnection conn,
    List<String> fileList, String name, String platformId) async {
  try {
    logger.info('开始遍历目录: $dirPath'); 
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
Future<bool> _isDuplicateRecord(MySqlConnection conn, String filePath,
    String name, String platformId) async {
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
  final String _logFilePath;
  final Mutex _logFileMutex = Mutex();
  final Queue<Future<void>> _logQueue = Queue<Future<void>>();
  Completer<void> _flushCompleter = Completer<void>();

  Logger({String logFilePath = 'process_log.txt'}) : _logFilePath = logFilePath;

  // 基本日志写入函数
  Future<void> _log(String level, String message, [StackTrace? stackTrace]) async {
    final completer = Completer<void>();
    _logQueue.add(completer.future);
    final logContent = '\n[${DateTime.now().toIso8601String()}] $level: $message${stackTrace != null ? '\n$stackTrace' : ''}';
    
    await _logFileMutex.acquire();
    try {
      await File(_logFilePath).writeAsString(logContent, mode: FileMode.append);
      completer.complete();
      _checkQueue();
    } catch (e) {
      completer.completeError(e);
    } finally {
      _logFileMutex.release();
    }
  }

  void _checkQueue() {
    if (_logQueue.isNotEmpty) {
      _logQueue.removeFirst().then((_) => _checkQueue());
    } else {
      if (!_flushCompleter.isCompleted) _flushCompleter.complete();
    }
  }

  // 在Isolate终止前调用
  Future<void> ensureLogsFlushed() async {
    if (_logQueue.isNotEmpty) {
      await _flushCompleter.future;
      _flushCompleter = Completer<void>();
    }
  }

  // 不同级别的日志写入
  void info(String message) => _log('INFO', message);
  void warning(String message) => _log('WARNING', message);
  void error(String message, [StackTrace? stackTrace]) => _log('ERROR', message, stackTrace);
  void debug(String message) {
    if (_globalSettings['enableDebugLogging'] == true) {
      _log('DEBUG', message);
    }
  }
  void fatal(String message, [StackTrace? stackTrace]) => _log('FATAL', message, stackTrace);
}


