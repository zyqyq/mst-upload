import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'web_server_launcher.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:webview_windows/webview_windows.dart' as webview_windows;

class DemoPage extends StatefulWidget {
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  const DemoPage({Key? key, this.onEnter, this.onExit}) : super(key: key);

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  // 处理遮罩状态
  bool _isProcessing = false;
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

  final TextEditingController _controller = TextEditingController();
  String _parsedInfo = '';
  // 用于监听输入框变化
  late final VoidCallback _textListener;
  // 标记是否为手动输入且路径存在且解析正常
  bool _showConfirmForManual = false;

  // 记录拷贝到public的文件绝对路径
  final List<String> _copiedFiles = [];
  // Flutter WebView控制器
  WebViewController? _webViewController;
  // Windows平台WebView控制器
  webview_windows.WebviewController? _windowsWebViewController;
  String? _pendingRelativePath;
  bool _isWebViewInitialized = false;

  @override
  void initState() {
    super.initState();
    widget.onEnter?.call();
    _textListener = () async {
      if (!mounted) return; // 防止组件销毁后继续执行
      final inputPath = _controller.text;
      final file = File(inputPath);
      final exists = await file.exists();
      final parsed = _parseFileName(inputPath.split('/').last);
      if (mounted) {
        // 确保组件仍然挂载
        setState(() {
          if (exists) {
            _parsedInfo = parsed;
          } else {
            _parsedInfo = '路径不存在';
          }
          // 只有手动输入、路径存在且解析正常时，显示"确认"
          _showConfirmForManual =
              exists && parsed != '无法解析' && parsed != '仅能解析L1B类型文件';
        });
      }
    };
    _controller.addListener(_textListener);
    _setupEnvironment().then((_) {
      if (!mounted) return; // 防止异步操作完成时组件已销毁
      // 仅在本地调试且未发布时预置路径
      if (!kDebugMode) {
        _controller.text = '';
      } else {
        _controller.text =
            '/Users/zyqyq/Program/数据集/L1B/202408/20240801/OQZQB_MSTR01_PSPP_L1B_30M_20240801110000_V01.00_M.TXT';
      }
      // 预置路径后自动解析
      _parsedInfo = _parseFileName(_controller.text.split('/').last);
      _initializeWebView();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.text.isNotEmpty) {
          _handleFileCopyAndNotify(_controller.text);
        }
      });
    }).catchError((error) {
      print('环境设置失败: $error');
    });
  }

  Future<void> _setupEnvironment() async {
    if (!mounted) return; // 提前检查组件状态

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
      if (mounted) {
        // 确保组件还在挂载状态
        _webServerLauncher = WebServerLauncher();
        try {
          _webServerPort =
              await _webServerLauncher!.startServer(pythonPath, distPath);
        } catch (e) {
          print('启动Web服务器失败: $e');
        }
      }
    }
  }

  void _initializeWebView() {
    // 确保WebView只初始化一次且组件仍然挂载
    if ((_webViewController != null || _windowsWebViewController != null) ||
        !mounted) {
      return;
    }

    try {
      if (Platform.isWindows) {
        // Windows平台使用webview_windows
        _windowsWebViewController = webview_windows.WebviewController();
        _initializeWindowsWebView();
      } else {
        // 其他平台使用webview_flutter
        _webViewController = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (url) {
                if (mounted) {
                  setState(() {
                    _isWebViewInitialized = true;
                  });
                  if (_pendingRelativePath != null &&
                      _webViewController != null) {
                    _webViewController!.runJavaScript(
                        "window.app && window.app.setFilepath('${_pendingRelativePath!}')");
                    _pendingRelativePath = null;
                  }
                }
              },
              onPageStarted: (url) {
                // 页面开始加载时重置状态
                if (mounted) {
                  setState(() {
                    _isWebViewInitialized = false;
                  });
                }
              },
              onWebResourceError: (error) {
                print('WebView资源加载错误: ${error.description}');
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
    } catch (e) {
      print('WebView初始化错误: $e');
    }
  }

  // 初始化Windows WebView
  Future<void> _initializeWindowsWebView() async {
    try {
      await _windowsWebViewController!.initialize();
      await _windowsWebViewController!.setBackgroundColor(Colors.transparent);
      // 设置其他WebView选项

      // 注册页面加载完成的回调
      _windowsWebViewController!.loadingState.listen((event) {
        if (event == webview_windows.LoadingState.navigationCompleted &&
            mounted) {
          setState(() {
            _isWebViewInitialized = true;
          });
          if (_pendingRelativePath != null) {
            _windowsWebViewController!.executeScript(
                "window.app && window.app.setFilepath('${_pendingRelativePath!}')");
            _pendingRelativePath = null;
          }
        }
      });

      // 根据不同环境加载不同的URL
      if (_webServerLauncher != null && _webServerLauncher!.isRunning) {
        // 如果HTTP服务器已启动，使用其URL
        await _windowsWebViewController!
            .loadUrl('http://127.0.0.1:$_webServerPort');
      } else {
        // 否则使用开发服务器
        await _windowsWebViewController!.loadUrl('http://127.0.0.1:8081');
      }
    } catch (e) {
      print('Windows WebView初始化错误: $e');
    }
  }

  @override
  void dispose() {
    // 先移除监听器防止内存泄露
    _controller.removeListener(_textListener);
    _controller.dispose();

    // 清理WebView资源
    if (Platform.isWindows && _windowsWebViewController != null) {
      try {
        // 清理Windows WebView资源
        _windowsWebViewController!.dispose();
      } catch (e) {
        print('清理Windows WebView错误: $e');
      }
      _windowsWebViewController = null;
    } else if (_webViewController != null) {
      try {
        // 停止WebView加载
        _webViewController?.loadRequest(Uri.parse('about:blank'));
        // 清空导航代理，防止回调延迟执行
        _webViewController?.setNavigationDelegate(NavigationDelegate());
        // 清空JavaScript通道
        _webViewController?.clearCache();
        _webViewController?.clearLocalStorage();
      } catch (e) {
        print('清理WebView错误: $e');
      }
      _webViewController = null;
    }

    // 清理其他状态
    _isWebViewInitialized = false;
    _pendingRelativePath = null;

    widget.onExit?.call();
    _deleteCopiedFiles();

    // 关闭Web服务器
    try {
      _webServerLauncher?.stopServer();
      _webServerLauncher = null;
    } catch (e) {
      print('关闭Web服务器错误: $e');
    }

    super.dispose();
  }

  Future<void> _pickFile() async {
    if (!mounted) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null && mounted) {
      setState(() {
        _controller.text = result.files.single.path!;
        _parsedInfo = _parseFileName(result.files.single.name);
        _showConfirmForManual = false; // 浏览方式不显示确认
      });
      await _handleFileCopyAndNotify(_controller.text);
    }
  }

  Future<void> _handleFileCopyAndNotify(String srcPath) async {
    if (!mounted) return;

    final srcFile = File(srcPath);
    if (!await srcFile.exists()) return;
    final fileName = srcFile.uri.pathSegments.last;
    final destDir = Directory(PUBLIC_DIR_PATH);
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final destPath = path.join(PUBLIC_DIR_PATH, fileName);

    try {
      await srcFile.copy(destPath);
      _copiedFiles.add(destPath);
      print('文件已拷贝: $srcPath 到 $destPath');

      // 对于HTTP服务器，使用相对于服务器根目录的路径
      final relativePath = '/$fileName';
      _pendingRelativePath = relativePath;

      if (_webViewController != null && _isWebViewInitialized && mounted) {
        _webViewController!.runJavaScript('''
          if (window.app && typeof window.app.setFilepath === "function") {
            window.app.setFilepath('$relativePath');
          } else {
            console.error('window.app.setFilepath 不可用');
          }
        ''');
      }
    } catch (e) {
      print('文件拷贝失败: $e');
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
    if (type != 'L1B') {
      return '仅能解析L1B类型文件';
    }
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
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
    });

    // 检查解析结果
    if (_parsedInfo == '无法解析' || _parsedInfo == '仅能解析L1B类型文件') {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('提示'),
            content: Text(_parsedInfo),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('确定'),
              ),
            ],
          ),
        );
      }
      setState(() {
        _isProcessing = false;
      });
      return;
    }

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

      if (mounted) {
        _copiedFiles.add(destPath);
        _pendingRelativePath = relativePath;

        // 读取处理后的文件第11行
        final file = File(destPath);
        if (await file.exists()) {
          final lines = await file.readAsLines();
          if (lines.length >= 11) {
            final line11 = lines[10]; // 第11行索引为10
            final regex = RegExp(
                r'#quantitative indicators:\s*(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)');
            final match = regex.firstMatch(line11);
            if (match != null && match.groupCount >= 6) {
              final a = match.group(5); // 倒数第二个数
              final b = match.group(6); // 最后一个数
              setState(() {
                _parsedInfo = '方差对称度: $a -> $b';
              });
            }
          }
        }

        if (_webViewController != null && _isWebViewInitialized && mounted) {
          _webViewController!.runJavaScript('''
            if (window.app && typeof window.app.setFilepath === "function") {
              window.app.setFilepath('$relativePath');
            } else {
              console.error('window.app.setFilepath 不可用');
            }
          ''');
        }
      }
    } catch (e) {
      print('处理文件失败: $e');
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
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
                        onPressed: _showConfirmForManual
                            ? () async {
                                await _handleFileCopyAndNotify(
                                    _controller.text);
                                if (mounted) {
                                  setState(() {
                                    // _showConfirmForManual = false;
                                  });
                                }
                              }
                            : null,
                        child: Text('原始'),
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
                  child: Stack(
                    children: [
                      Builder(
                        builder: (context) {
                          try {
                            if (Platform.isWindows) {
                              // Windows平台使用webview_windows
                              if (_windowsWebViewController != null) {
                                return webview_windows.Webview(
                                    _windowsWebViewController!);
                              }
                            } else {
                              // 其他平台使用webview_flutter
                              if (_webViewController != null) {
                                return WebViewWidget(
                                  controller: _webViewController!,
                                );
                              }
                            }
                            return Center(
                              child: CircularProgressIndicator(),
                            );
                          } catch (e) {
                            print('WebView小部件错误: $e');
                            return Center(
                              child: Text('WebView加载失败，请重试'),
                            );
                          }
                        },
                      ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black.withOpacity(0.4),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                    strokeWidth: 5,
                                  ),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  '正在处理...请稍候',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 18),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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
