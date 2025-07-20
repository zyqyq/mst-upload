import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as webview_windows;
import 'transfer_page.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'demo_page.dart'; // 新增: 导入 DemoPage
import 'dart:async'; // 添加: 引入 Timer 所需的库
import 'dart:io'; // 添加: 导入 dart:io 库以使用 File
import 'dart:convert'; // 添加: 导入 dart:convert 库以使用 json
import 'file_operations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:liquid_progress_indicator_v2/liquid_progress_indicator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await webview_windows.WebviewController().initialize();
  }
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(900, 600), // 设置默认窗口大小
    minimumSize: Size(800, 500), // 设置最小窗口大小
    center: true, // 设置窗口居中
    title: "MST上传", // 设置窗口标题
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MST上传',
      theme: ThemeData(
        fontFamily: Platform.isWindows
            ? 'Microsoft YaHei'
            : (Platform.isMacOS ? 'PingFang SC' : null),
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
  late final ValueNotifier<int> _countdownNotifier;
  late final ValueNotifier<int> _progressNotifier;
  bool _isPaused = false;
  Timer? _syncTimer;
  late double _navWidthRatio;
  final double _defaultNavWidthRatio = 0.25;
  final double _demoNavWidthRatio = 0.125;
  final Size _defaultWindowSize = const Size(900, 600);
  final Size _demoWindowSize = const Size(1200, 700);

  List<Widget> get _pages => [
        TransferPage(
          countdownNotifier: _countdownNotifier,
          onTogglePause: _handleTogglePause,
        ),
        DemoPage(
          key: _selectedIndex == 1
              ? const ValueKey('demo_page')
              : null, // 修改: 使用固定key而不是UniqueKey
          onEnter: _onDemoEnter,
          onExit: _onDemoExit,
        ),
        HistoryPage(),
        SettingsPage(key: _settingsPageKey, onSettingsSaved: _onSettingsSaved),
      ];

  @override
  void initState() {
    super.initState();
    _settingsPageKey = GlobalKey<SettingsPageState>();
    _countdownNotifier = ValueNotifier<int>(0);
    _progressNotifier = ValueNotifier<int>(0);
    _navWidthRatio = _defaultNavWidthRatio;
    _startSyncTimer();
  }

  void _onDemoEnter() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        setState(() {
          _navWidthRatio = _demoNavWidthRatio;
        });
    });
    await windowManager.setSize(_demoWindowSize);
  }

  void _onDemoExit() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        setState(() {
          _navWidthRatio = _defaultNavWidthRatio;
        });
    });
    await windowManager.setSize(_defaultWindowSize);
  }

  // 添加: 读取 setting.json 文件
  Future<Map<String, dynamic>> _readSettings() async {
    const defaultSettings = <String, dynamic>{};
    final settingsFile = File('settings.json');

    try {
      final settingsContent = await settingsFile.readAsString();
      print("同步频率${settingsContent}");

      if (settingsContent.trim().isEmpty) {
        final settingsContent = await settingsFile.readAsString();
        print("同步频率${settingsContent}");
        if (settingsContent.trim().isEmpty) {
          print('settings.json 文件内容为空，使用默认设置');
          return defaultSettings;
        }
      }

      return json.decode(settingsContent) as Map<String, dynamic>;
    } on FileSystemException catch (e) {
      print('文件访问异常: ${e.message}，使用默认设置');
      return defaultSettings;
    } on FormatException catch (e) {
      print('JSON格式错误: ${e.message}，使用默认设置');
      return defaultSettings;
    }
  }

  Future<void> _startSyncTimer() async {
    _syncTimer?.cancel(); // 添加: 取消旧的定时器
    final settings = await _readSettings();
    //print(settings);
    final syncFrequency =
        int.tryParse(settings['syncFrequency'].toString()) ?? 30;
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

  void _handlePageSwitch(int newIndex) {
    // 只处理窗口自适应逻辑，不再直接调用 DemoPage 的 onEnter/onExit
    if (_selectedIndex == 1 && newIndex != 1) {
      _onDemoExit();
    }
    if (newIndex == 1 && _selectedIndex != 1) {
      _onDemoEnter();
    }
    setState(() {
      _selectedIndex = newIndex;
    });
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
                      width: MediaQuery.of(context).size.width * _navWidthRatio,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: LiquidLinearProgressIndicator(
                                value: progress / 100.0,
                                valueColor: AlwaysStoppedAnimation(
                                    Theme.of(context)
                                        .primaryColor
                                        .withAlpha((0.5 * 255).toInt())),
                                backgroundColor: Theme.of(context)
                                    .primaryColor
                                    .withAlpha((0.3 * 255).toInt()),
                                borderColor: Theme.of(context)
                                    .primaryColor
                                    .withAlpha((0.3 * 255).toInt()),
                                borderWidth: 0.0,
                                borderRadius: 0.0,
                                direction: Axis.vertical,
                              ),
                            ),
                          ),
                          NavigationRail(
                            backgroundColor: Colors.transparent, // 设置背景为透明
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
                                  _handlePageSwitch(index);
                                }
                              } else {
                                _handlePageSwitch(index);
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
                                icon: Icon(Icons.slideshow),
                                selectedIcon: Icon(Icons.slideshow),
                                label: Text('演示'), // "演示"调整到第二项
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
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: _pages[_selectedIndex.clamp(0, _pages.length - 1)],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
