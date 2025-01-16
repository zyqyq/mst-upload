import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path; // 添加路径处理库
import 'dart:convert'; // 添加json处理库
import 'upload_Para.dart'; // 导入 upload_Para.dart 文件
import 'file_operations.dart'; // 导入 file_operations.dart 文件
import 'main.dart';
import 'dart:async'; // 引入 Timer 所需的库

class TransferPage extends StatefulWidget {
  final GlobalKey<CountdownTextState> countdownKey;
  final Function(bool) onTogglePause; // 添加: 接收回调函数

  TransferPage({required this.countdownKey, required this.onTogglePause}); // 修改: 添加构造函数参数

  @override
  _TransferPageState createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  bool _isHovered = false;
  bool _isDatabaseConnected = false;
  late Timer _connectionCheckTimer;
  String _currentMode = '全局';
  bool _isPaused = false;

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
                  groupValue: _currentMode, // 修改: 使用 _currentMode
                  onChanged: (value) {
                    setState(() {
                      _currentMode = value!; // 修改: 使用 _currentMode
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ),
              ListTile(
                title: Text('顺序'),
                leading: Radio(
                  value: '顺序',
                  groupValue: _currentMode, // 修改: 使用 _currentMode
                  onChanged: (value) {
                    setState(() {
                      _currentMode = value!; // 修改: 使用 _currentMode
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

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      widget.countdownKey.currentState?.updateRemainingSeconds(
          widget.countdownKey.currentState!._remainingSeconds); // 更新倒计时显示
      // 通过回调函数更新 MyHomePage 中的 _isPaused 状态
      widget.onTogglePause(_isPaused);
    });
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
        final syncFrequency = settings['syncFrequency'] ?? 5;

        return Scaffold(
          appBar: AppBar(
            title: Text('Transfer Page'),
            actions: <Widget>[
              IconButton(
                icon: Icon(_isPaused ? Icons.play_circle_filled : Icons.pause_circle_filled), // 修改: 根据 _isPaused 更新图标
                onPressed: _togglePause,
                tooltip: _isPaused ? '继续' : '暂停', // 修改: 根据 _isPaused 更新文字
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
                    onTap: () {
                      // 同步逻辑
                    },
                    child: Column(
                      children: <Widget>[
                        Icon(_isHovered ? Icons.sync : Icons.cloud_upload,
                          size: 128),
                        SizedBox(height: 16),
                        // 使用 CountdownText 小部件来显示倒计时
                        _isHovered
                            ? Text('单击以立即同步')
                            : CountdownText(
                                remainingSeconds: 0, // 初始值不重要，因为会通过 GlobalKey 更新
                                key: widget.countdownKey,
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
    final countdownText =
        '${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}后执行同步';
    return Text(countdownText);
  }
}
