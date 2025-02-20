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
        logDebug('处理 $filePath Python 脚本输出: ${result.stdout}');
      }
      if (result.stderr.isNotEmpty) {
        print('stderr: ${result.stderr}');
        logWarning('优化 $filePath 时Python脚本错误输出: ${result.stderr}');
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
        logDebug('处理 $filePath 时Python 脚本输出: ${result.stdout}');
      }
      if (result.stderr.isNotEmpty) {
        print('stderr: ${result.stderr}');
        logWarning('转换 $filePath 时Python 脚本错误输出: ${result.stderr}');
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

// 新增连接池类
class ConnectionPool {
  final List<MySqlConnection> _pool = [];
  final ConnectionSettings _settings;
  final int _maxSize;
  final Mutex _lock = Mutex();

  ConnectionPool(this._settings, {int maxSize = 5}) : _maxSize = maxSize;

  Future<MySqlConnection> getConnection() async {
    await _lock.acquire();
    try {
      // 尝试复用空闲连接
      while (_pool.isNotEmpty) {
        final conn = _pool.removeLast();
        try {
          // 使用简单的查询来检查连接是否有效
          await conn.query('SELECT 1');
          return conn;
        } catch (_) {
          // 连接无效，关闭并移除
          await conn.close();
        }
      }
      // 创建新连接
      final conn = await MySqlConnection.connect(_settings);
      return conn;
    } finally {
      _lock.release();
    }
  }

  Future<void> releaseConnection(MySqlConnection conn) async {
    await _lock.acquire();
    try {
      if (_pool.length < _maxSize) {
        try {
          // 使用简单的查询来检查连接是否有效
          await conn.query('SELECT 1');
          _pool.add(conn);
        } catch (_) {
          // 连接无效，关闭并移除
          await conn.close();
        }
      } else {
        await conn.close();
      }
    } finally {
      _lock.release();
    }
  }

  Future<void> closeAll() async {
    await _lock.acquire();
    try {
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

  final dbParams = ConnectionSettings(
    host: settings['databaseAddress'],
    port: int.parse(settings['databasePort']),
    user: settings['databaseUsername'],
    password: settings['databasePassword'],
    db: settings['databaseName'],
  );

  MySqlConnection? conn;
  try {
    conn = await MySqlConnection.connect(dbParams);
    await conn.query('USE `${settings['databaseName']}`');
    logDebug('数据库连接成功');
  } catch (e, stackTrace) {
    logError('无法连接到数据库: $e', stackTrace);
    sendPort.send(false);
    return;
  }

  final connectionPool = ConnectionPool(dbParams, maxSize: 1); // 初始化连接池
  try {
    // 确保连接在使用前是有效的
    conn = await connectionPool.getConnection();
    await processFile(filePath, folderPath, conn, showName, name, platformId, settings);
    logDebug('文件处理完成: $filePath');
    sendPort.send(true);
  } catch (e, stackTrace) {
    logError('文件处理失败: $filePath', stackTrace);
    sendPort.send(false);
  } finally {
    try {
      if (conn != null) {
        await connectionPool.releaseConnection(conn);
      }
    } catch (_) {}
    logDebug('数据库连接关闭');
    await connectionPool.closeAll(); // 清理连接池
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
    int processedFiles) async {
  final int maxIsolates = Platform.numberOfProcessors ~/ 2; // 动态调整隔离线程数
  final List<Isolate> isolates = [];
  final List<ReceivePort> receivePorts = [];
  int totalFiles = fileList.length;
  int activeIsolates = 0;

  logInfo('开始多线程处理文件，最大线程数 $maxIsolates');
  for (final filePath in fileList) {
    if (activeIsolates >= maxIsolates) {
      await receivePorts[0].first;
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
      },
    ));
    logDebug('启动 Isolate: $filePath');
    print('启动 Isolate: $filePath');

    activeIsolates++;
  }

  for (final receivePort in receivePorts) {
    await receivePort.first;
    processedFiles++;
    progressNotifier.value = (processedFiles * 90 / totalFiles + 10).round();
  }

  for (final isolate in isolates) {
    isolate.kill(priority: Isolate.immediate);
  }
  logInfo('多线程处理文件完成');
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

  final folderPath = _globalSettings['sourceDataPath'];
  final startTime = DateTime.now();

  MySqlConnection? conn;
  try {
    conn = await MySqlConnection.connect(dbParams);
    await conn.query('USE `${_globalSettings['databaseName']}`');
    logDebug('数据库连接成功');
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

  final fileList = <String>[];
  await _traverseDirectory(folderPath, conn, fileList, name, platformId);
  progressNotifier.value = 10;
  int processedFiles = 0;

  final connectionPool = ConnectionPool(dbParams, maxSize: 5); // 初始化连接池

  await processFilesInParallel(fileList, folderPath, connectionPool, showName, name,
      platformId, _globalSettings, progressNotifier, processedFiles);

  try {
    await conn?.close();
  } catch (_) {
  }
  logDebug('数据库连接关闭');

  final endTime = DateTime.now();
  final runTime = endTime.difference(startTime).inMilliseconds;
  print('所有文件处理完成，程序运行时间：${runTime / 1000.0}秒');

  logInfo('所有文件处理完成，程序运行时间: ${runTime / 1000.0}秒 处理文件总数: ${fileList.length}');

  progressNotifier.value = 0;

  await connectionPool.closeAll(); // 清理连接池
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
    final fileName = path.basename(filePath);
    final parts = fileName.split('_');
    if (parts.length < 6) {
      logWarning('文件名格式错误: $fileName');
      return true;
    }

    final dateTimeStr = parts[5];
    if (dateTimeStr.length != 14) {
      logWarning('时间戳格式错误: $dateTimeStr');
      return true;
    }

    final dt = DateTime.tryParse(
      '${dateTimeStr.substring(0, 4)}-'
      '${dateTimeStr.substring(4, 6)}-'
      '${dateTimeStr.substring(6, 8)} '
      '${dateTimeStr.substring(8, 10)}:'
      '${dateTimeStr.substring(10, 12)}:'
      '${dateTimeStr.substring(12)}'
    );

    if (dt == null) {
      logWarning('无法解析时间戳: $dateTimeStr');
      return true;
    }

    final MSTStr = parts[5];
    final MST = MSTStr == 'M' ? 0 : 1;
    final checkSql = '''
      SELECT COUNT(*) 
      FROM `${_globalSettings['DeviceTableNme']}`
      WHERE Time = ? 
        AND name = ? 
        AND MST = ? 
        AND Platform_id = ?
    ''';

    final result = await conn.query(
      checkSql,
      [dt.toUtc(), name, MST, platformId],
    );

    return (result.first[0] as int) > 0;
  } catch (e, stackTrace) {
    logError('查重失败: $e', stackTrace);
    return true;
  }
}