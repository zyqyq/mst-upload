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
      await _serverProcess?.kill();
      _serverProcess = null;
    }
  }

  bool get isRunning => _isRunning;
  int get port => _port;
  String get webRoot => _webRoot;
}
