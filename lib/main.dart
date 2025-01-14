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

  final List<Widget> _pages = [
    TransferPage(),
    HistoryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            extended: true, // 添加: 使侧边栏扩展以显示标题
            backgroundColor: Theme.of(context).primaryColor.withAlpha((0.3 * 255).toInt()), // 使用主题的主色调并调整透明度
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
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
  }
}

