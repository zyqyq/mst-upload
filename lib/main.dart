import 'package:flutter/material.dart';
import 'transfer_page.dart'; // 导入TransferPage
import 'history_page.dart'; // 导入HistoryPage
import 'settings_page.dart'; // 导入SettingsPage
import 'dart:async'; // 添加: 引入 Timer 所需的库
import 'dart:io'; // 添加: 导入 dart:io 库以使用 File
import 'dart:convert'; // 添加: 导入 dart:convert 库以使用 json
import 'file_operations.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MST上传',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

bool _isProcessing = false;

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  late final GlobalKey<SettingsPageState> _settingsPageKey;
  late final ValueNotifier<int> _countdownNotifier; // 修改: 使用 ValueNotifier<int>
  late final ValueNotifier<int>
      _progressNotifier; // 新增: 使用 ValueNotifier<int> 来跟踪进度
  late final List<Widget> _pages;
  bool _isPaused = false;
  Timer? _syncTimer; // 添加: 定义 Timer 变量来存储当前的定时器实例

  @override
  void initState() {
    super.initState();
    _settingsPageKey = GlobalKey<SettingsPageState>();
    _countdownNotifier = ValueNotifier<int>(0); // 修改: 初始化 ValueNotifier
    _progressNotifier = ValueNotifier<int>(0); // 新增: 初始化进度 ValueNotifier
    _pages = [
      TransferPage(
        countdownNotifier: _countdownNotifier,
        onTogglePause: _handleTogglePause,
      ), // 新增: 传递进度 ValueNotifier
      HistoryPage(),
      SettingsPage(
          key: _settingsPageKey,
          onSettingsSaved: _onSettingsSaved), // 添加: 传递回调函数
    ];
    _startSyncTimer();
  }

  // 添加: 读取 setting.json 文件
  Future<Map<String, dynamic>> _readSettings() async {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    print(settingsContent);
    if (settingsContent.trim().isEmpty) {
      print('settings.json 文件内容为空，使用默认设置');
    }
    return json.decode(settingsContent);
  }

  Future<void> _startSyncTimer() async {
    _syncTimer?.cancel(); // 添加: 取消旧的定时器
    final settings = await _readSettings();
    //print(settings);
    final syncFrequency = int.parse(settings['syncFrequency'].toString()) ?? 5;
    print(syncFrequency);
    int _remainingSeconds = syncFrequency * 60;
    _countdownNotifier.value = _remainingSeconds; // 修改: 初始化倒计时
    _syncTimer = Timer.periodic(Duration(seconds: 1), (_) async {
      if (_isProcessing) {
        // 如果正在处理文件，则跳过本次回调
        print(
            "Skipping timer callback because processFileswithTimer is running.");
        return;
      }
      // 修改: 存储新的定时器实例
      //print(_countdownNotifier.value);
      if (!_isPaused && _remainingSeconds > 0 && _countdownNotifier.value > 0) {
        // 修改: 添加 _isPaused 检查
        _remainingSeconds--;
        _countdownNotifier.value = _remainingSeconds; // 修改: 更新 ValueNotifier
      } else if (_remainingSeconds == 0 || _countdownNotifier.value == 0) {
        _remainingSeconds == 0;
        _countdownNotifier.value == 0;
        print("processFileswithTimer");
        await processFileswithTimer();
        _remainingSeconds = syncFrequency * 60;
        _countdownNotifier.value = _remainingSeconds; // 修改: 重置 ValueNotifier
      }
    });
  }

  Future<void> processFileswithTimer() async {
    // 执行文件同步操作
    if (_isProcessing) return; // 如果已经在处理，则直接返回
    _isProcessing = true;
    try {
      print("processFiles");
      await processFiles(context, _progressNotifier);
    } finally {
      _isProcessing = false;
    }
  }

  void _handleTogglePause(bool isPaused) {
    // 添加: 处理暂停状态的回调函数
    setState(() {
      _isPaused = isPaused;
    });
  }

  // 添加: 处理设置保存的回调函数
  void _onSettingsSaved() {
    _startSyncTimer(); // 重新启动同步定时器
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                ValueListenableBuilder<int>(
                  valueListenable: _progressNotifier,
                  builder: (context, progress, child) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.blue.shade900,
                            Colors.blue.shade100,
                          ],
                          stops: [
                            progress / 100.0,
                            1.0,
                          ],
                        ),
                      ),
                      child: NavigationRail(
                        extended: true,
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: (int index) async {
                          if (_selectedIndex == 2 &&
                              _settingsPageKey
                                      .currentState?.hasUnsavedChanges ==
                                  true) {
                            final shouldPop = await _settingsPageKey
                                .currentState
                                ?.showUnsavedChangesDialog();
                            if (shouldPop == true) {
                              setState(() {
                                _selectedIndex = index;
                              });
                            }
                          } else {
                            setState(() {
                              _selectedIndex = index;
                            });
                          }
                        },
                        labelType: NavigationRailLabelType.none,
                        leading: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: ValueListenableBuilder<int>(
                            valueListenable: _progressNotifier,
                            builder: (context, progress, child) {
                              if (progress != 0 && progress != 100) {
                                return Text('进度: $progress%',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold));
                              } else {
                                return Text('MST上传',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold));
                              }
                            },
                          ),
                        ),
                        destinations: [
                          NavigationRailDestination(
                            icon: Icon(Icons.file_upload),
                            selectedIcon: Icon(Icons.file_upload),
                            label: Text('传输'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.history),
                            selectedIcon: Icon(Icons.history),
                            label: Text('历史'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings),
                            selectedIcon: Icon(Icons.settings),
                            label: Text('设置'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: _pages[_selectedIndex],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
