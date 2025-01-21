import 'package:flutter/material.dart';
import 'dart:io'; // 添加dart:io库以使用File类
import 'dart:convert'; // 添加dart:convert库以使用json.decode和json.encode

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

  Future<void> _loadLog() async {
    final file = File('process_log.txt');
    if (await file.exists()) {
      final contents = await file.readAsString();
      final lines = contents.split('\n');
      final filteredLines = lines.where((line) => !line.startsWith('处理文件列表')).toList();
      setState(() {
        _logController.text = filteredLines.join('\n');
      });
    }
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
    ) ?? false; // 如果用户没有选择任何按钮，则默认返回 false
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('历史页面'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: 16),
            ElevatedButton( // 新增: 添加清除按钮
              onPressed: () async {
                final shouldClear = await _showClearConfirmationDialog();
                if (shouldClear) {
                  _clearLog();
                }
              },
              child: Text('清除'),
            ),
            SizedBox(height: 16), // 新增: 添加间距
            Expanded(
              child: TextField(
                controller: _logController,
                decoration: InputDecoration(
                  labelText: '处理日志',
                  border: OutlineInputBorder(),
                ),
                maxLines: null,
                readOnly: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}