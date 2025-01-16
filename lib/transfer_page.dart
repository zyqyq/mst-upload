import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path; // 添加路径处理库
import 'dart:convert'; // 添加json处理库
import 'upload_Para.dart'; // 导入 upload_Para.dart 文件
import 'file_operations.dart'; // 导入 file_operations.dart 文件
import 'dart:async'; // 引入 Timer 所需的库

class TransferPage extends StatefulWidget {
  @override
  _TransferPageState createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  bool _isHovered = false;

  @override
  void dispose() {
    super.dispose();
  }

  // 读取 setting.json 文件
  Future<Map<String, dynamic>> _readSettings() async {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    return json.decode(settingsContent);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _readSettings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('加载设置失败: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text('设置为空'));
        }

        final settings = snapshot.data!;
        final syncFrequency = settings['syncFrequency'] ?? 5; // 默认5分钟

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: processFiles,
                  child: Column(
                    children: <Widget>[
                      Icon(_isHovered ? Icons.sync : Icons.cloud_upload, size: 128),
                      SizedBox(height: 16),
                      Text(_isHovered ? '单击立即同步' : '$syncFrequency分钟后再次同步'),
                    ],
                  ),
                ),
                onEnter: (_) {
                  if (!_isHovered) {
                    setState(() {
                      _isHovered = true;
                    });
                  }
                },
                onExit: (_) {
                  if (_isHovered) {
                    setState(() {
                      _isHovered = false;
                    });
                  }
                },
              ),
              SizedBox(height: 32),
              ElevatedButton(
                onPressed: processFiles,
                child: Text('传输页面'),
              ),
            ],
          ),
        );
      },
    );
  }
}
