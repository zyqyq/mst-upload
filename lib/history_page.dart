import 'package:flutter/material.dart';
import 'dart:io'; // 添加dart:io库以使用File类
import 'dart:convert'; // 添加dart:convert库以使用json.decode和json.encode
import 'package:url_launcher/url_launcher.dart'; // 添加url_launcher库以使用launch方法
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class HistoryPage extends StatefulWidget {
  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _logController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  // 修改: _loadLog 方法返回 Future<String>
  Future<String> _loadLog() async {
    final file = File('process_log.txt');
    if (await file.exists()) {
      final contents = await file.readAsString();
      final lines = contents.split('\n');
      final filteredLines =
          lines.where((line) => line.trim().isNotEmpty).toList();
      // 倒序排列日志行
      return filteredLines.reversed.toList().join('\n');
    }
    return ''; // 如果文件不存在，返回空字符串
  }

  // 新增: 清除日志内容的方法
  Future<void> _clearLog() async {
    final file = File('process_log.txt');
    if (await file.exists()) {
      await file.writeAsString('');
      setState(() {
        _logController.text = '';
      });
    }
  }

  // 新增: 显示确认对话框的方法
  Future<bool> _showClearConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('确认清除日志'),
              content: Text('您确定要清除所有日志内容吗？'),
              actions: <Widget>[
                TextButton(
                  child: Text('取消'),
                  onPressed: () {
                    Navigator.of(context).pop(false); // 返回 false 表示不清除日志
                  },
                ),
                TextButton(
                  child: Text('确认'),
                  onPressed: () {
                    Navigator.of(context).pop(true); // 返回 true 表示清除日志
                  },
                ),
              ],
            );
          },
        ) ??
        false; // 如果用户没有选择任何按钮，则默认返回 false
  }

  // 新增: 打开日志文件的方法
  Future<void> _openLog() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(path.join(directory.path, 'process_log.txt'));
    print(file.path);
    if (await file.exists()) {
      final url = Uri.file(file.path);
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('日志文件不存在')),
      );
    }
  }

  // 修改: 根据日志级别设置不同的颜色
  Color _getLogColor(String line) {
    if (line.contains('INFO')) {
      return Colors.green[100]!;
    } else if (line.contains('DEBUG')) {
      return Colors.blue[100]!;
    } else if (line.contains('ERROR')) {
      return Colors.red[100]!;
    } else if (line.contains('WARNING')) {
      return Colors.orange[100]!;
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('历史页面'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.open_in_browser),
            onPressed: _openLog,
            tooltip: '打开日志',
          ),
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              final shouldClear = await _showClearConfirmationDialog();
              if (shouldClear) {
                _clearLog();
              }
            },
            tooltip: '清除日志',
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: FutureBuilder<String>(
                future: _loadLog(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    final lines = snapshot.data?.split('\n') ?? [];
                    return ListView.builder(
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        return Container(
                          color: _getLogColor(line),
                          padding: EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(line),
                        );
                      },
                    );
                  } else {
                    return Center(child: CircularProgressIndicator());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}