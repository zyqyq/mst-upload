import 'package:flutter/material.dart';
import 'transfer_page.dart'; // 导入TransferPage
import 'history_page.dart'; // 导入HistoryPage
import 'settings_page.dart'; // 导入SettingsPage
import 'dart:async'; // 添加: 引入 Timer 所需的库
import 'dart:io'; // 添加: 导入 dart:io 库以使用 File
import 'dart:convert'; // 添加: 导入 dart:convert 库以使用 json

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

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  late final GlobalKey<SettingsPageState> _settingsPageKey;
  late final ValueNotifier<int> _countdownNotifier; // 修改: 使用 ValueNotifier<int>
  late final List<Widget> _pages;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _settingsPageKey = GlobalKey<SettingsPageState>();
    _countdownNotifier = ValueNotifier<int>(0); // 修改: 初始化 ValueNotifier
    _pages = [
      TransferPage(countdownNotifier: _countdownNotifier, onTogglePause: _handleTogglePause), // 修改: 使用 ValueNotifier
      HistoryPage(),
      SettingsPage(),
    ];
    _startSyncTimer();
  }

  // 添加: 读取 setting.json 文件
  Future<Map<String, dynamic>> _readSettings() async {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    return json.decode(settingsContent);
  }

  void _startSyncTimer() async {
    final settings = await _readSettings();
    final syncFrequency = int.parse(settings['syncFrequency'].toString()) ?? 5;
    int _remainingSeconds = syncFrequency * 60;
    _countdownNotifier.value = _remainingSeconds; // 修改: 初始化倒计时
    Timer.periodic(Duration(seconds: 1), (_) {
      if (!_isPaused && _remainingSeconds > 0) { // 修改: 添加 _isPaused 检查
        _remainingSeconds--;
        _countdownNotifier.value = _remainingSeconds; // 修改: 更新 ValueNotifier
      } else if (_remainingSeconds <= 0) {
        processFileswithTimer();
        _remainingSeconds = syncFrequency * 60;
        _countdownNotifier.value = _remainingSeconds; // 修改: 重置 ValueNotifier
      }
    });
  }

  void processFileswithTimer() {
    // 取消当前同步定时器
    // 重新启动同步定时器
    // 执行文件同步操作
    processFiles();
  }

  // 添加: 文件同步方法
  void processFiles() {
    // 文件同步逻辑
  }

  void _handleTogglePause(bool isPaused) { // 添加: 处理暂停状态的回调函数
    setState(() {
      _isPaused = isPaused;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope( // 使用 PopScope 替代 WillPopScope
      canPop: true, // 默认情况下允许返回
      child: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                NavigationRail(
                  extended: true, // 添加: 使侧边栏扩展以显示标题
                  backgroundColor: Theme.of(context).primaryColor.withAlpha((0.3 * 255).toInt()), // 使用主题的主色调并调整透明度
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) async {
                    if (_selectedIndex == 2 && _settingsPageKey.currentState?.hasUnsavedChanges == true) {
                      final shouldPop = await _settingsPageKey.currentState?.showUnsavedChangesDialog();
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
                  labelType: NavigationRailLabelType.none, // 修改: 将 labelType 设置为 NavigationRailLabelType.none
                  leading: Padding( // 添加: 使用 leading 参数来添加标题
                    padding: const EdgeInsets.all(16.0),
                    child: Text('MST上传', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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