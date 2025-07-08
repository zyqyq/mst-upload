import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'web_server_launcher.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class DemoPage extends StatefulWidget {
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  const DemoPage({Key? key, this.onEnter, this.onExit}) : super(key: key);

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  // 当前应用路径
  static final String _appPath = path.dirname(Platform.resolvedExecutable);
  // 根据调试模式和设置动态确定的公共目录路径
  late final String PUBLIC_DIR_PATH;
  // 动态确定的Web服务器端口
  int _webServerPort = 18080;

  // Web服务器启动器
  WebServerLauncher? _webServerLauncher;
  // 是否处于调试模式
  bool _isDebugMode = false;

  final TextEditingController _controller = TextEditingController(
    text:
        '/Users/zyqyq/Program/数据集/L1B/202408/20240801/OQZQB_MSTR01_PSPP_L1B_30M_20240801110000_V01.00_M.TXT',
  );
  String _parsedInfo = '';

  // 记录拷贝到public的文件绝对路径
  final List<String> _copiedFiles = [];
  WebViewController? _webViewController;
  String? _pendingRelativePath;
  bool _isWebViewInitialized = false;

  @override
  void initState() {
    super.initState();
    widget.onEnter?.call();
    _setupEnvironment().then((_) {
      _parsedInfo = _parseFileName(_controller.text.split('/').last);
      _initializeWebView();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleFileCopyAndNotify(_controller.text);
      });
    });
  }

  Future<void> _setupEnvironment() async {
    // 读取settings.json配置
    final settingsFile = File('settings.json');
    if (await settingsFile.exists()) {
      final settingsContent = await settingsFile.readAsString();
      final settings = json.decode(settingsContent);
      _isDebugMode = settings['enableDebugLogging'] == true;
    }

    // 根据当前环境确定公共目录路径
    final bool isRunningInRelease = !kDebugMode;

    if (isRunningInRelease) {
      // 发布模式 - 使用打包后的dist目录
      final appDir = Directory(_appPath);
      final String distPath =
          path.join(appDir.path, 'data', 'app-webview', 'dist');
      PUBLIC_DIR_PATH = distPath;

      // 确保目录存在
      final distDir = Directory(distPath);
      if (!await distDir.exists()) {
        await distDir.create(recursive: true);
      }
    } else if (_isDebugMode) {
      // 调试模式 - 使用相对路径的public目录
      PUBLIC_DIR_PATH =
          path.join(Directory.current.path, 'app-webview', 'public');
    } else {
      // 非调试模式 - 启动HTTP服务器指向dist目录
      final String distPath =
          path.join(Directory.current.path, 'app-webview', 'dist');
      PUBLIC_DIR_PATH = distPath;

      // 确保目录存在
      final distDir = Directory(distPath);
      if (!await distDir.exists()) {
        await distDir.create(recursive: true);
      }

      // 读取Python解释器路径
      String pythonPath = 'python';
      final settingsFile = File('settings.json');
      if (await settingsFile.exists()) {
        final settingsContent = await settingsFile.readAsString();
        final settings = json.decode(settingsContent);
        if (settings['pythonInterpreterPath'] != null) {
          pythonPath = settings['pythonInterpreterPath'];
        }
      }

      // 启动Web服务器
      _webServerLauncher = WebServerLauncher();
      try {
        _webServerPort =
            await _webServerLauncher!.startServer(pythonPath, distPath);
      } catch (e) {
        print('启动Web服务器失败: $e');
      }
    }
  }

  void _initializeWebView() {
    if (_webViewController == null) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              setState(() {
                _isWebViewInitialized = true;
              });
              if (_pendingRelativePath != null && _webViewController != null) {
                _webViewController!.runJavaScript(
                    "window.app && window.app.setFilepath('${_pendingRelativePath!}')");
                _pendingRelativePath = null;
              }
            },
          ),
        );

      // 根据不同环境加载不同的URL
      if (_webServerLauncher != null && _webServerLauncher!.isRunning) {
        // 如果HTTP服务器已启动，使用其URL
        _webViewController!
            .loadRequest(Uri.parse('http://127.0.0.1:$_webServerPort'));
      } else {
        // 否则使用开发服务器
        _webViewController!.loadRequest(Uri.parse('http://127.0.0.1:8081'));
      }
    }
  }

  @override
  void dispose() {
    _webViewController = null;
    widget.onExit?.call();
    _deleteCopiedFiles();

    // 关闭Web服务器
    _webServerLauncher?.stopServer();

    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _controller.text = result.files.single.path!;
        _parsedInfo = _parseFileName(result.files.single.name);
      });
      await _handleFileCopyAndNotify(_controller.text);
    }
  }

  Future<void> _handleFileCopyAndNotify(String srcPath) async {
    final srcFile = File(srcPath);
    if (!await srcFile.exists()) return;
    final fileName = srcFile.uri.pathSegments.last;
    final destDir = Directory(PUBLIC_DIR_PATH);
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final destPath = path.join(PUBLIC_DIR_PATH, fileName);
    await srcFile.copy(destPath);
    _copiedFiles.add(destPath);
    print('文件已拷贝: $srcPath 到 $destPath');

    // 对于HTTP服务器，使用相对于服务器根目录的路径
    final relativePath = '/$fileName';
    _pendingRelativePath = relativePath;

    if (_webViewController != null && _isWebViewInitialized) {
      _webViewController!.runJavaScript('''
        if (window.app && typeof window.app.setFilepath === "function") {
          window.app.setFilepath('$relativePath');
        } else {
          console.error('window.app.setFilepath 不可用');
        }
      ''');
    }
  }

  Future<void> _deleteCopiedFiles() async {
    for (final path in _copiedFiles) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (e) {
        print('删除文件失败: $path, 错误: $e');
      }
    }
    _copiedFiles.clear();
  }

  String _parseFileName(String fileName) {
    final parts = fileName.split('_');
    if (parts.length < 8) return '无法解析';
    String type = parts[3].toUpperCase(); // L1B/L2
    String timeStr = parts[5];
    String mstRaw = parts[7].toUpperCase(); // M 或 ST
    String mst = '';
    if (mstRaw == 'M.TXT') {
      mst = 'M';
    } else if (mstRaw == 'ST.TXT') {
      mst = 'ST';
    } else {
      mst = mstRaw;
    }
    String timeFmt = '';
    if (timeStr.length == 14) {
      timeFmt =
          '${timeStr.substring(0, 4)}-${timeStr.substring(4, 6)}-${timeStr.substring(6, 8)} '
          '${timeStr.substring(8, 10)}:${timeStr.substring(10, 12)}:${timeStr.substring(12, 14)}';
    }
    return '类型: $type $mst    时间: $timeFmt';
  }

  Future<void> _handleProcessFile() async {
    try {
      final settingsFile = File('settings.json');
      final settingsContent = await settingsFile.readAsString();
      final settings = json.decode(settingsContent);
      final pythonPath = settings['pythonInterpreterPath'];
      final scriptPath = settings['optimizationProgramPath'];
      final srcPath = _controller.text;
      final fileName = File(srcPath).uri.pathSegments.last;
      final dotIdx = fileName.lastIndexOf('.');
      final processedName = dotIdx > 0
          ? fileName.substring(0, dotIdx) +
              '_processed' +
              fileName.substring(dotIdx)
          : fileName + '_processed';
      final destPath = path.join(PUBLIC_DIR_PATH, processedName);
      final relativePath = '/$processedName';

      // 确保PUBLIC_DIR_PATH目录存在
      final destDir = Directory(path.dirname(destPath));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final result =
          await Process.run(pythonPath, [scriptPath, srcPath, destPath]);
      if (result.stdout != null && result.stdout.toString().isNotEmpty) {
        print('stdout: ${result.stdout}');
      }
      if (result.stderr != null && result.stderr.toString().isNotEmpty) {
        print('stderr: ${result.stderr}');
      }
      _copiedFiles.add(destPath);
      _pendingRelativePath = relativePath;

      if (_webViewController != null && _isWebViewInitialized) {
        _webViewController!.runJavaScript('''
          if (window.app && typeof window.app.setFilepath === "function") {
            window.app.setFilepath('$relativePath');
          } else {
            console.error('window.app.setFilepath 不可用');
          }
        ''');
      }
    } catch (e) {
      print('处理文件失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('演示')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            labelText: '文件路径',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _pickFile,
                        child: Text('浏览'),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 24),
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: _parsedInfo),
                          readOnly: true,
                          maxLines: 1,
                          style: TextStyle(fontSize: 16),
                          decoration: InputDecoration(
                            labelText: '文件信息',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _handleProcessFile,
                        child: Text('处理'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _webViewController != null
                      ? WebViewWidget(
                          controller: _webViewController!,
                        )
                      : Center(
                          child: CircularProgressIndicator(),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class L1BData {
  final double height;
  final double? rv1, rv2, rv3, rv4, rv5;
  L1BData(this.height, this.rv1, this.rv2, this.rv3, this.rv4, this.rv5);
}

class PieSlice {
  final String label;
  final int value;

  PieSlice(this.label, this.value);
}
