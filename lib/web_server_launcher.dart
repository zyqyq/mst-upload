import 'dart:io';
import 'dart:convert';
import 'dart:async';

class WebServerLauncher {
  Process? _serverProcess;
  int _port = 18080;
  String _webRoot = '';
  bool _isRunning = false;

  Future<int> startServer(String pythonPath, String webRoot) async {
    if (_isRunning) {
      return _port;
    }

    _webRoot = webRoot;
    bool serverStarted = false;

    while (!serverStarted && _port < 18100) {
      try {
        // 尝试启动服务器
        _serverProcess = await Process.start(
          pythonPath,
          ['-m', 'http.server', _port.toString()],
          workingDirectory: _webRoot,
        );

        // 监听标准输出
        _serverProcess!.stdout.transform(utf8.decoder).listen((data) {
          // 可选：如需调试可打开
          // print('Web server output: $data');
        });

        // 监听错误输出
        _serverProcess!.stderr.transform(utf8.decoder).listen((data) {
          if (data.contains('Address already in use')) {
            // 不输出端口占用错误
            _port++;
          } else {
            // 其他错误可选输出
            // print('Web server error: $data');
          }
        });

        // 等待一小段时间，确认服务器是否启动成功
        await Future.delayed(Duration(milliseconds: 500));

        // 尝试发送请求，检查服务器是否可用
        try {
          final socket = await Socket.connect('localhost', _port,
              timeout: Duration(seconds: 1));
          await socket.close();
          serverStarted = true;
          _isRunning = true;
          print('Web server started on port $_port');
        } catch (e) {
          // 不输出端口占用相关的连接失败
          await _serverProcess?.kill();
          _port++;
        }
      } catch (e) {
        // 不输出端口占用相关的启动失败
        _port++;
      }
    }

    if (!serverStarted) {
      throw Exception(
          'Failed to start web server after trying ports 18080-18100');
    }

    return _port;
  }

  Future<void> stopServer() async {
    if (_serverProcess != null) {
      print('Stopping web server on port $_port');
      _isRunning = false;

      try {
        // 在Windows系统上首先尝试优雅关闭
        if (Platform.isWindows) {
          // 发送终止信号
          _serverProcess?.kill();

          // 等待进程终止，设置超时
          bool processExited = false;
          int timeoutMs = 3000; // 3秒超时
          int checkIntervalMs = 100;
          int elapsedMs = 0;

          while (!processExited && elapsedMs < timeoutMs) {
            await Future.delayed(Duration(milliseconds: checkIntervalMs));
            elapsedMs += checkIntervalMs;

            try {
              // 检查进程是否还在运行
              final result = await Process.run('tasklist',
                  ['/FI', 'PID eq ${_serverProcess!.pid}', '/FO', 'CSV']);
              processExited =
                  !result.stdout.toString().contains('${_serverProcess!.pid}');
            } catch (e) {
              // 如果检查失败，假设进程已退出
              processExited = true;
            }
          }

          // 如果进程还没有退出，强制终止
          if (!processExited) {
            try {
              await Process.run(
                  'taskkill', ['/F', '/PID', '${_serverProcess!.pid}']);
              print('强制终止Web服务器进程: ${_serverProcess!.pid}');
            } catch (e) {
              print('强制终止进程失败: $e');
            }
          }
        } else {
          // 非Windows系统
          final killResult = await _serverProcess?.kill();
          if (killResult != true) {
            try {
              await Process.run('kill', ['-9', '${_serverProcess!.pid}']);
            } catch (e) {
              print('强制终止进程失败: $e');
            }
          }
        }
      } catch (e) {
        print('终止进程出错: $e');
      } finally {
        // 清理监听器和资源
        // 注意：不能直接取消已经建立的监听器，这里只是确保引用被清理
        _serverProcess = null;
      }
    }
  }

  bool get isRunning => _isRunning;
  int get port => _port;
  String get webRoot => _webRoot;
}
