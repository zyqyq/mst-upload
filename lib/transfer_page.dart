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
  late Timer _syncTimer; // 添加同步定时器
  int _remainingSeconds = 0; // 添加剩余秒数变量

  // 引入 GlobalKey
  final GlobalKey<CountdownTextState> _countdownKey = GlobalKey<CountdownTextState>(); // 修正 GlobalKey 类型

  String _currentMode = '全局'; // 添加模式选择变量

  @override
  void initState() {
    super.initState();
    _checkDatabaseConnection();
    _connectionCheckTimer = Timer.periodic(Duration(minutes: 1), (_) {
      _checkDatabaseConnection();
    });
    _startSyncTimer(); // 启动同步定时器
  }

  @override
  void dispose() {
    _connectionCheckTimer.cancel();
    _syncTimer.cancel(); // 取消同步定时器
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

  void _startSyncTimer() async {
    final settings = await _readSettings();
    final syncFrequency = int.parse(settings['syncFrequency'].toString()) ?? 5; // 将 syncFrequency 转换为 int 类型
    _remainingSeconds = syncFrequency * 60; // 设置剩余秒数
    _syncTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        _countdownKey.currentState?.updateRemainingSeconds(_remainingSeconds); // 更新倒计时
      } else {
        processFileswithTimer();
      }
    });
  }

  void processFileswithTimer() {
    // 取消当前同步定时器
    _syncTimer.cancel();
    // 重新启动同步定时器
    _startSyncTimer();
    // 执行文件同步操作
    processFiles();
  }

  void _showModeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('选择模式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text('全局'),
                leading: Radio(
                  value: '全局',
                  groupValue: _currentMode,
                  onChanged: (value) {
                    setState(() {
                      _currentMode = value!;
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ),
              ListTile(
                title: Text('顺序'),
                leading: Radio(
                  value: '顺序',
                  groupValue: _currentMode,
                  onChanged: (value) {
                    setState(() {
                      _currentMode = value!;
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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

        return Scaffold(
          appBar: AppBar(
            title: Text('Transfer Page'),
            actions: <Widget>[
              IconButton(
                icon: Icon(Icons.pause_circle_filled),
                onPressed: processFileswithTimer,
                tooltip: '暂停/继续',
                mouseCursor: SystemMouseCursors.click,
              ),
              IconButton(
                icon: Icon(Icons.settings),
                onPressed: _showModeDialog,
                tooltip: '模式选择',
                mouseCursor: SystemMouseCursors.click,
              ),
              IconButton(
                icon: Icon(Icons.info),
                onPressed: () {
                  // 详细信息逻辑
                },
                tooltip: '详细信息',
                mouseCursor: SystemMouseCursors.click,
              ),
            ],
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: processFileswithTimer,
                    child: Column(
                      children: <Widget>[
                        Icon(_isHovered ? Icons.sync : Icons.cloud_upload,
                            size: 128),
                        SizedBox(height: 16),
                        // 使用 CountdownText 小部件来显示倒计时
                        CountdownText(
                          remainingSeconds: _remainingSeconds,
                          key: _countdownKey,
                        ),
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
                                      color: _isDatabaseConnected
                                          ? Colors.green
                                          : Colors.red,
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
          ),
        );
      },
    );
  }
}

// 新增 CountdownText 小部件
class CountdownText extends StatefulWidget {
  final int remainingSeconds;

  CountdownText({Key? key, required this.remainingSeconds}) : super(key: key);

  @override
  CountdownTextState createState() => CountdownTextState();
}

class CountdownTextState extends State<CountdownText> {
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.remainingSeconds;
  }

  // 新增方法来更新剩余秒数
  void updateRemainingSeconds(int newSeconds) {
    setState(() {
      _remainingSeconds = newSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final countdownText = '${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}后执行同步';
    return Text(countdownText);
  }
}
