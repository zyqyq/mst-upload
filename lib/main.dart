import 'package:flutter/material.dart';
import 'transfer_page.dart'; // 导入TransferPage
import 'history_page.dart'; // 导入HistoryPage
import 'settings_page.dart'; // 导入SettingsPage

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

  // 添加: 为 SettingsPage 添加 GlobalKey
  late final GlobalKey<SettingsPageState> _settingsPageKey; // 修改: 将 _SettingsPageState 改为 SettingsPageState

  final List<Widget> _pages = [
    TransferPage(),
    HistoryPage(),
    SettingsPage(), // 使用无参数构造函数
  ];

  @override
  void initState() {
    super.initState();
    _settingsPageKey = GlobalKey<SettingsPageState>(); // 初始化 GlobalKey
    _pages[2] = SettingsPage(key: _settingsPageKey); // 使用 GlobalKey 更新 _pages 列表中的 SettingsPage
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