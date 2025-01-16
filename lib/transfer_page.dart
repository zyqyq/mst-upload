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
  bool _isDatabaseConnected = false;
  late Timer _connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkDatabaseConnection();
    _connectionCheckTimer = Timer.periodic(Duration(minutes: 1), (_) {
      _checkDatabaseConnection();
    });
  }

  @override
  void dispose() {
    _connectionCheckTimer.cancel();
    super.dispose();
  }

  // 读取 setting.json 文件
  Future<Map<String, dynamic>> _readSettings() async {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    return json.decode(settingsContent);
  }

  Future<void> _checkDatabaseConnection() async {
    final settings = await _readSettings();
    final dbAddress = settings['databaseAddress'];
    final dbPort = settings['databasePort'];
    final dbUser = settings['databaseUsername'];
    final dbPass = settings['databasePassword'];
    final dbName = settings['databaseName'];

    try {
      final conn = await MySqlConnection.connect(ConnectionSettings(
        host: dbAddress,
        port: int.parse(dbPort),
        user: dbUser,
        password: dbPass,
        db: dbName,
      ));
      await conn.close();
      setState(() {
        _isDatabaseConnected = true;
      });
    } catch (e) {
      setState(() {
        _isDatabaseConnected = false;
      });
    }
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Text('数据库'),
                                SizedBox(width: 8),
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isDatabaseConnected ? Colors.green : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text('地址: ${settings['databaseAddress']}'),
                            Text('名称: ${settings['databaseName']}'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('卡片2'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('卡片3'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
