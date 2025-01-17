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
  late ValueNotifier<bool> _isHoveredNotifier;
  late ValueNotifier<bool> _isDatabaseConnectedNotifier;
  late ValueNotifier<bool> _isPausedNotifier;
  late Timer _connectionCheckTimer;
  String _currentMode = '全局';

  @override
  void initState() {
    super.initState();
    _isHoveredNotifier = ValueNotifier<bool>(false);
    _isDatabaseConnectedNotifier = ValueNotifier<bool>(false);
    _isPausedNotifier = ValueNotifier<bool>(false);
    _checkDatabaseConnection();
    _connectionCheckTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _checkDatabaseConnection();
    });
  }

  @override
  void dispose() {
    _connectionCheckTimer.cancel();
    _isHoveredNotifier.dispose();
    _isDatabaseConnectedNotifier.dispose();
    _isPausedNotifier.dispose();
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
      _isDatabaseConnectedNotifier.value = true;
    } catch (e) {
      _isDatabaseConnectedNotifier.value = false;
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
    _isPausedNotifier.value = !_isPausedNotifier.value;
    widget.countdownKey.currentState?.updateRemainingSeconds(
        widget.countdownKey.currentState!._remainingSecondsNotifier.value); // 修改: 使用公共方法和 ValueNotifier
    widget.onTogglePause(_isPausedNotifier.value);
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
              ValueListenableBuilder<bool>(
                valueListenable: _isPausedNotifier,
                builder: (context, isPaused, child) {
                  return IconButton(
                    icon: Icon(isPaused ? Icons.play_circle_filled : Icons.pause_circle_filled),
                    onPressed: _togglePause,
                    tooltip: isPaused ? '继续' : '暂停',
                    mouseCursor: SystemMouseCursors.click,
                  );
                },
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
                        ValueListenableBuilder<bool>(
                          valueListenable: _isHoveredNotifier,
                          builder: (context, isHovered, child) {
                            return Icon(isHovered ? Icons.sync : Icons.cloud_upload,
                              size: 128);
                          },
                        ),
                        SizedBox(height: 16),
                        // 使用 CountdownText 小部件来显示倒计时
                        ValueListenableBuilder<bool>(
                          valueListenable: _isHoveredNotifier,
                          builder: (context, isHovered, child) {
                            return isHovered
                                ? Text('单击以立即同步')
                                : CountdownText(
                                    remainingSeconds: 0,
                                    key: widget.countdownKey,
                                  );
                          },
                        ),
                      ],
                    ),
                  ),
                  onEnter: (_) {
                    _isHoveredNotifier.value = true;
                  },
                  onExit: (_) {
                    _isHoveredNotifier.value = false;
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
                              ValueListenableBuilder<bool>(
                                valueListenable: _isDatabaseConnectedNotifier,
                                builder: (context, isConnected, child) {
                                  return Row(
                                    children: <Widget>[
                                      Text('数据库'),
                                      SizedBox(width: 8),
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isConnected ? Colors.green : Colors.red,
                                        ),
                                      ),
                                    ],
                                  );
                                },
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
  late ValueNotifier<int> _remainingSecondsNotifier;

  @override
  void initState() {
    super.initState();
    _remainingSecondsNotifier = ValueNotifier<int>(widget.remainingSeconds);
  }

  @override
  void dispose() {
    _remainingSecondsNotifier.dispose();
    super.dispose();
  }

  // 新增方法来更新剩余秒数
  void updateRemainingSeconds(int newSeconds) {
    _remainingSecondsNotifier.value = newSeconds;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _remainingSecondsNotifier,
      builder: (context, remainingSeconds, child) {
        final countdownText =
            '${remainingSeconds ~/ 60}:${(remainingSeconds % 60).toString().padLeft(2, '0')}后执行同步';
        return Text(countdownText);
      },
    );
  }
}
