import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';

class DemoPage extends StatefulWidget {
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  const DemoPage({Key? key, this.onEnter, this.onExit}) : super(key: key);

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  // 定义public目录路径为常量，便于统一管理和修改
  static const String PUBLIC_DIR_PATH = '/Users/zyqyq/Program/app-webview/app-webview/public';
  
  final TextEditingController _controller = TextEditingController(
    text:
        '/Users/zyqyq/Program/数据集/L1B/202408/20240801/OQZQB_MSTR01_PSPP_L1B_30M_20240801110000_V01.00_M.TXT',
  );
  String _parsedInfo = '';

  // 记录拷贝到public的文件绝对路径
  final List<String> _copiedFiles = [];
  late final WebViewController _webViewController;
  String? _pendingRelativePath;

  @override
  void initState() {
    super.initState();
    widget.onEnter?.call();
    _parsedInfo = _parseFileName(_controller.text.split('/').last);
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (_pendingRelativePath != null) {
              _webViewController.runJavaScript(
                  "window.app && window.app.setFilepath('${_pendingRelativePath!}')");
              _pendingRelativePath = null;
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('http://127.0.0.1:8081'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleFileCopyAndNotify(_controller.text);
    });
  }

  @override
  void dispose() {
    widget.onExit?.call();
    _deleteCopiedFiles();
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
    final destDir = Directory(PUBLIC_DIR_PATH); // 使用常量代替硬编码路径
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final destPath = '$PUBLIC_DIR_PATH/$fileName'; // 使用常量代替硬编码路径
    await srcFile.copy(destPath);
    _copiedFiles.add(destPath);
    print('文件已拷贝: $srcPath');
    final relativePath = '/$fileName'; // public下的相对路径
    _pendingRelativePath = relativePath;
    // 若页面已加载完成可立即注入，否则等 onPageFinished
    _webViewController.runJavaScript('''
      if (window.app && typeof window.app.setFilepath === "function") {
        window.app.setFilepath('$relativePath');
      }
    ''');
  }

  Future<void> _deleteCopiedFiles() async {
    for (final path in _copiedFiles) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
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
      // 1. 读取 settings.json
      final settingsFile = File('settings.json');
      final settingsContent = await settingsFile.readAsString();
      final settings = json.decode(settingsContent);
      final pythonPath = settings['pythonInterpreterPath'];
      final scriptPath = settings['optimizationProgramPath'];
      // 2. 计算新文件名
      final srcPath = _controller.text;
      final fileName = File(srcPath).uri.pathSegments.last;
      final dotIdx = fileName.lastIndexOf('.');
      final processedName = dotIdx > 0
          ? fileName.substring(0, dotIdx) +
              '_processed' +
              fileName.substring(dotIdx)
          : fileName + '_processed';
      final destPath = '$PUBLIC_DIR_PATH/$processedName'; // 使用常量代替硬编码路径
      final relativePath = '/$processedName';
      // 3. 调用python脚本
      final result =
          await Process.run(pythonPath, [scriptPath, srcPath, destPath]); // 使用常量代替硬编码路径
      if (result.stdout != null && result.stdout.toString().isNotEmpty) {
        print('stdout: ${result.stdout}');
      }
      if (result.stderr != null && result.stderr.toString().isNotEmpty) {
        print('stderr: ${result.stderr}');
      }
      // 4. 记录新文件，通知web
      _copiedFiles.add(destPath);
      _pendingRelativePath = relativePath;
      _webViewController.runJavaScript('''
        if (window.app && typeof window.app.setFilepath === "function") {
          window.app.setFilepath('$relativePath');
        }
      ''');
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
                  child: WebViewWidget(
                    controller: _webViewController,
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
