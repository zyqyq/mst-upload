import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // 添加文件选择器库
import 'dart:io'; // 添加dart:io库以使用Directory和File类
import 'dart:convert'; // 添加dart:convert库以使用json.decode和json.encode
import 'package:mysql1/mysql1.dart'; // 添加 mysql1 库以进行数据库连接

class SettingsPage extends StatefulWidget {
  final Key? key; // 添加: 添加 key 参数

  SettingsPage({this.key}) : super(key: key); // 添加: 传递 key 参数给父类

  @override
  SettingsPageState createState() => SettingsPageState(); // 修改: 返回 SettingsPageState 类型
}

class SettingsPageState extends State<SettingsPage> {
  final TextEditingController _sourceDataPathController = TextEditingController();
  final TextEditingController _conversionProgramPathController = TextEditingController();
  final TextEditingController _syncFrequencyController = TextEditingController(); // 添加同步频率输入框的控制器
  final TextEditingController _databaseAddressController = TextEditingController();
  final TextEditingController _databasePortController = TextEditingController();
  final TextEditingController _databasePasswordController = TextEditingController();
  final TextEditingController _databaseUsernameController = TextEditingController(); // 添加用户名输入框的控制器
  final TextEditingController _databaseNameController = TextEditingController(); // 添加数据库名称输入框控制器
  final TextEditingController _showNameController = TextEditingController(); // 新增 show_name 输入框控制器
  final TextEditingController _platformIdController = TextEditingController(); // 新增 Platform_id 输入框控制器
  final TextEditingController _nameController = TextEditingController(); // 新增 name 输入框控制器
  bool _isPasswordVisible = false; // 添加标志来跟踪密码是否可见

  bool _hasUnsavedChanges = false; // 添加标志来跟踪是否有未保存的更改

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final file = File('settings.json');
    if (await file.exists()) {
      final contents = await file.readAsString();
      final Map<String, dynamic> settings = json.decode(contents);
      setState(() {
        _sourceDataPathController.text = settings['sourceDataPath'] ?? '';
        _conversionProgramPathController.text = settings['conversionProgramPath'] ?? '';
        _syncFrequencyController.text = settings['syncFrequency'] ?? ''; // 加载同步频率
        _databaseAddressController.text = settings['databaseAddress'] ?? '';
        _databasePortController.text = settings['databasePort'] ?? '';
        _databasePasswordController.text = settings['databasePassword'] ?? '';
        _databaseUsernameController.text = settings['databaseUsername'] ?? ''; // 加载用户名
        _databaseNameController.text = settings['databaseName'] ?? ''; // 加载数据库名称
        _showNameController.text = settings['show_name'] ?? ''; // 加载 show_name
        _platformIdController.text = settings['Platform_id'] ?? ''; // 加载 Platform_id
        _nameController.text = settings['name'] ?? ''; // 加载 name
        _hasUnsavedChanges = false; // 重置标志
      });
    }
  }

  Future<void> _saveSettings() async {
    final file = File('settings.json');
    final settings = {
      'sourceDataPath': _sourceDataPathController.text,
      'conversionProgramPath': _conversionProgramPathController.text,
      'syncFrequency': _syncFrequencyController.text, // 保存同步频率
      'databaseAddress': _databaseAddressController.text,
      'databasePort': _databasePortController.text,
      'databasePassword': _databasePasswordController.text,
      'databaseUsername': _databaseUsernameController.text, // 保存用户名
      'databaseName': _databaseNameController.text, // 保存数据库名称
      'show_name': _showNameController.text, // 保存 show_name
      'Platform_id': _platformIdController.text, // 保存 Platform_id
      'name': _nameController.text, // 保存 name
    };
    await file.writeAsString(json.encode(settings));
    setState(() {
      _hasUnsavedChanges = false; // 重置标志
    });
  }

  Future<void> _selectFolder(TextEditingController controller) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        controller.text = result;
        _hasUnsavedChanges = true; // 设置标志
      });
    }
  }

  Future<void> _selectFile(TextEditingController controller) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['py']);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        controller.text = result.files.first.path!;
        _hasUnsavedChanges = true; // 设置标志
      });
    }
  }

  void _validatePaths() {
    final sourceDataPath = _sourceDataPathController.text;
    final conversionProgramPath = _conversionProgramPathController.text;

    if (sourceDataPath.isNotEmpty && !Directory(sourceDataPath).existsSync()) {
      _showErrorDialog('源数据地址不是一个有效的文件夹路径');
      return;
    }

    if (conversionProgramPath.isNotEmpty && !File(conversionProgramPath).existsSync()) {
      _showErrorDialog('转换程序地址不是一个有效的 .py 文件');
      return;
    }

    // 如果所有路径都有效
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('所有路径有效')),
    );
    _saveSettings(); // 保存设置
  }

  Future<bool> _validateDatabaseConnection() async {
    final String host = _databaseAddressController.text;
    final int port = int.tryParse(_databasePortController.text) ?? 3306;
    final String user = _databaseUsernameController.text;
    final String password = _databasePasswordController.text;
    final String db = _databaseNameController.text;

    try {
      final connection = await MySqlConnection.connect(ConnectionSettings(
        host: host,
        port: port,
        user: user,
        password: password,
        db: db,
      ));
      await connection.close();
      return true;
    } catch (e) {
      if (e is SocketException) {
        print('数据库连接失败: ${e.message} (OS Error: ${e.osError?.message}, errno = ${e.osError?.errorCode}), address = $host, port = $port');
      } else {
        print('数据库连接失败: $e');
      }
      return false;
    }
  }

  void _validateDatabaseParameters() async {
    final bool isValid = await _validateDatabaseConnection();
    if (isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('数据库参数有效')),
      );
      _saveSettings(); // 保存设置
    } else {
      _showErrorDialog('数据库参数无效或连接失败');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('错误'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: Text('确定'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool> showUnsavedChangesDialog() async { // 添加: 显示未保存更改的对话框
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('未保存更改'),
          content: Text('您有未保存的更改，是否要保存？'),
          actions: <Widget>[
            TextButton(
              child: Text('取消修改'),
              onPressed: () {
                Navigator.of(context).pop(false); // 返回 false 表示不保存更改
              },
            ),
            TextButton(
              child: Text('确认保存'),
              onPressed: () {
                _saveSettings(); // 保存更改
                Navigator.of(context).pop(true); // 返回 true 表示保存更改
              },
            ),
          ],
        );
      },
    ) ?? false; // 如果用户没有选择任何按钮，则默认返回 false
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges; // 添加 getter 方法

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('设置'),
        actions: <Widget>[
          if (_hasUnsavedChanges) // 根据标志决定是否显示“保存”按钮
            IconButton(
              icon: Icon(Icons.save),
              onPressed: _validatePaths,
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16.0),
        children: <Widget>[
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('源数据地址', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _sourceDataPathController,
                          decoration: InputDecoration(
                            labelText: '文件夹路径',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                        ),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        height: 56, // 设置按钮高度与输入框相同
                        child: ElevatedButton(
                          onPressed: () => _selectFolder(_sourceDataPathController),
                          child: Text('选择文件夹'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10), // 添加间距
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('转换程序地址', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _conversionProgramPathController,
                          decoration: InputDecoration(
                            labelText: 'Python文件路径',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                        ),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        height: 56, // 设置按钮高度与输入框相同
                        child: ElevatedButton(
                          onPressed: () => _selectFile(_conversionProgramPathController),
                          child: Text('选择文件'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10), // 添加间距
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('同步频率', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // 修改: 同步频率
                  SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _syncFrequencyController, // 修改: 同步频率控制器
                          decoration: InputDecoration(
                            labelText: 'n分钟一次', // 修改: 后缀解释
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10), // 添加间距
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('数据库配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _databaseAddressController,
                    decoration: InputDecoration(
                      labelText: '数据库地址',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _databasePortController,
                    decoration: InputDecoration(
                      labelText: '端口号',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _databaseNameController, // 数据库名称输入框
                    decoration: InputDecoration(
                      labelText: '数据库名称',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _databaseUsernameController, // 用户名输入框
                    decoration: InputDecoration(
                      labelText: '用户名',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _databasePasswordController,
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible; // 切换密码可见性
                          });
                        },
                      ),
                    ),
                    obscureText: !_isPasswordVisible, // 根据标志决定是否隐藏密码
                    onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      ElevatedButton(
                        onPressed: _validateDatabaseParameters,
                        child: Text('校验有效性'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 10), // 添加间距
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('项目配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _showNameController, // show_name 输入框
                    decoration: InputDecoration(
                      labelText: 'show_name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _platformIdController, // Platform_id 输入框
                    decoration: InputDecoration(
                      labelText: 'Platform_id',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController, // name 输入框
                    decoration: InputDecoration(
                      labelText: 'name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _hasUnsavedChanges = true), // 设置标志
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}