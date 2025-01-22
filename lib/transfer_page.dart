import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path; // 添加路径处理库
import 'dart:convert'; // 添加json处理库
import 'file_operations.dart'; // 导入 file_operations.dart 文件
import 'main.dart';
import 'dart:async'; // 引入 Timer 所需的库
import 'package:intl/intl.dart';

class TransferPage extends StatefulWidget {
  final ValueNotifier<int> countdownNotifier; // 修改: 使用 ValueNotifier<int>
  final Function(bool) onTogglePause; // 添加: 接收回调函数

  TransferPage(
      {required this.countdownNotifier,
      required this.onTogglePause}); // 修改: 添加构造函数参数

  @override
  _TransferPageState createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  late ValueNotifier<bool> _isHoveredNotifier;
  late ValueNotifier<bool> _isDatabaseConnectedNotifier;
  late ValueNotifier<bool> _isPausedNotifier;
  late Timer _connectionCheckTimer;
  String _currentMode = '全局';
  late ValueNotifier<Map<String, dynamic>> _logSummaryNotifier; // 新增: 添加 ValueNotifier<Map<String, dynamic>> 用于存储日志摘要数据

  @override
  void initState() {
    super.initState();
    _isHoveredNotifier = ValueNotifier<bool>(false);
    _isDatabaseConnectedNotifier = ValueNotifier<bool>(false);
    _isPausedNotifier = ValueNotifier<bool>(false);
    _logSummaryNotifier = ValueNotifier<Map<String, dynamic>>({'count': -1, 'totalFiles': -1}); // 新增: 初始化 _logSummaryNotifier
    _checkDatabaseConnection();
    _getLogSummary().then((summary) {
        _logSummaryNotifier.value = summary;
      });
    _connectionCheckTimer = Timer.periodic(Duration(seconds: 60), (_) {
      _checkDatabaseConnection();
      _getLogSummary().then((summary) {
        _logSummaryNotifier.value = summary;
      });
    });
  }

  @override
  void dispose() {
    _connectionCheckTimer.cancel();
    _isHoveredNotifier.dispose();
    _isDatabaseConnectedNotifier.dispose();
    _isPausedNotifier.dispose();
    _logSummaryNotifier.dispose(); // 新增: 释放 _logSummaryNotifier
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
    widget.countdownNotifier.value =
        widget.countdownNotifier.value; // 修改: 使用 ValueNotifier
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

        return Scaffold(
          appBar: AppBar(
            title: Text('Transfer Page'),
            actions: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: _isPausedNotifier,
                builder: (context, isPaused, child) {
                  return IconButton(
                    icon: Icon(isPaused
                        ? Icons.play_circle_filled
                        : Icons.pause_circle_filled),
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
              mainAxisAlignment: MainAxisAlignment.end, // 修改: 将 mainAxisAlignment 从 end 改为 center
              children: <Widget>[
                Expanded(
                  child: Center( // 修改: 添加 Center 小部件
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          widget.countdownNotifier.value = 0; 
                        },
                        child:Center(
                        child: Column(
                          children: <Widget>[
                            SizedBox(height: 64),
                            ValueListenableBuilder<bool>(
                              valueListenable: _isHoveredNotifier,
                              builder: (context, isHovered, child) {
                                return Icon(
                                    isHovered ? Icons.sync : Icons.cloud_upload,
                                    size: 128);
                              },
                            ),
                            SizedBox(height: 16),
                            ValueListenableBuilder<bool>(
                              valueListenable: _isHoveredNotifier,
                              builder: (context, isHovered, child) {
                                return isHovered
                                    ? Text('单击以立即同步')
                                    : CountdownText(
                                        countdownNotifier: widget
                                            .countdownNotifier,
                                      );
                              },
                            ),
                          ],
                        ),
                        ),
                      ),
                      onEnter: (_) {
                        _isHoveredNotifier.value = true;
                      },
                      onExit: (_) {
                        _isHoveredNotifier.value = false;
                      },
                    ),
                  ),
                ),
                //SizedBox(height: 64),
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
                                      Text('数据库',style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold)),
                                      SizedBox(width: 8),
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isConnected
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              SizedBox(height: 8),
                              Text('ip: ${settings['databaseAddress']}'),
                              Text('db: ${settings['databaseName']}'),
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
                              ValueListenableBuilder<Map<String, dynamic>>(
                                valueListenable: _logSummaryNotifier,
                                builder: (context, summary, child) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text('同步统计',style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold)),
                                      SizedBox(height: 8),
                                      Text('今日同步次数: ${summary['count']}'),
                                      Text('处理文件总数: ${summary['totalFiles']}'),
                                    ],
                                  );
                                },
                              ),
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

  // 新增: 定义 _getLogSummary 方法
 Future<Map<String, dynamic>> _getLogSummary() async {
  final file = File('process_log.txt'); 
  if (await file.exists()) {
    final contents = await file.readAsLines(); // 逐行读取文件内容
    int todayCount = 0;
    int totalFiles = 0;
    final today = DateTime.now();
    final todayString = DateFormat('yyyy-MM-dd').format(today); // 格式化今天的日期

    for (final line in contents) {
      if (line.contains(todayString)) {
        todayCount++;
        final match = RegExp(r'处理文件总数: (\d+)').firstMatch(line);
        if (match != null) {
          totalFiles += int.parse(match.group(1)!);
        }
      }
    }
      return {'count': todayCount, 'totalFiles': totalFiles};
  } else {
    return {'count': -1, 'totalFiles': -1};
  }
}
}

// 新增 CountdownText 小部件
class CountdownText extends StatefulWidget {
  final ValueNotifier<int> countdownNotifier; // 修改: 使用 ValueNotifier<int>

  CountdownText({Key? key, required this.countdownNotifier})
      : super(key: key); // 修改: 使用 ValueNotifier

  @override
  CountdownTextState createState() => CountdownTextState();
}

class CountdownTextState extends State<CountdownText> {
  late ValueNotifier<int> _remainingSecondsNotifier;

  @override
  void initState() {
    super.initState();
    _remainingSecondsNotifier = ValueNotifier<int>(
        widget.countdownNotifier.value); // 修改: 初始化 ValueNotifier
    widget.countdownNotifier.addListener(_updateRemainingSeconds); // 添加: 添加监听器
  }

  @override
  void dispose() {
    widget.countdownNotifier
        .removeListener(_updateRemainingSeconds); // 添加: 移除监听器
    _remainingSecondsNotifier.dispose();
    super.dispose();
  }

  // 新增方法来更新剩余秒数
  void _updateRemainingSeconds() {
    _remainingSecondsNotifier.value = widget.countdownNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
  return ValueListenableBuilder<int>(
    valueListenable: _remainingSecondsNotifier,
    builder: (context, remainingSeconds, child) {
      String countdownText;
      if (remainingSeconds == -60) {
        countdownText = '手动同步模式';
      } else if (remainingSeconds == 0) {
        countdownText = '正在同步中';
      } else {
        countdownText = '${remainingSeconds ~/ 60}:${(remainingSeconds % 60).toString().padLeft(2, '0')}后执行同步';
      }
      return Text(countdownText);
    },
  );
}
}
