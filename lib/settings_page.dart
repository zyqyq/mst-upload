import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // 添加文件选择器库
import 'dart:io'; // 添加dart:io库以使用Directory和File类
import 'dart:convert'; // 添加dart:convert库以使用json.decode和json.encode

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _sourceDataPathController = TextEditingController();
  final TextEditingController _conversionProgramPathController = TextEditingController();
  final TextEditingController _uploadProgramPathController = TextEditingController();
  final TextEditingController _databaseAddressController = TextEditingController();
  final TextEditingController _databasePortController = TextEditingController();
  final TextEditingController _databasePasswordController = TextEditingController();

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
        _uploadProgramPathController.text = settings['uploadProgramPath'] ?? '';
        _databaseAddressController.text = settings['databaseAddress'] ?? '';
        _databasePortController.text = settings['databasePort'] ?? '';
        _databasePasswordController.text = settings['databasePassword'] ?? '';
        _hasUnsavedChanges = false; // 重置标志
      });
    }
  }

  Future<void> _saveSettings() async {
    final file = File('settings.json');
    final settings = {
      'sourceDataPath': _sourceDataPathController.text,
      'conversionProgramPath': _conversionProgramPathController.text,
      'uploadProgramPath': _uploadProgramPathController.text,
      'databaseAddress': _databaseAddressController.text,
      'databasePort': _databasePortController.text,
      'databasePassword': _databasePasswordController.text,
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
    final uploadProgramPath = _uploadProgramPathController.text;

    if (sourceDataPath.isNotEmpty && !Directory(sourceDataPath).existsSync()) {
      _showErrorDialog('源数据地址不是一个有效的文件夹路径');
      return;
    }

    if (conversionProgramPath.isNotEmpty && !File(conversionProgramPath).existsSync()) {
      _showErrorDialog('转换程序地址不是一个有效的 .py 文件');
      return;
    }

    if (uploadProgramPath.isNotEmpty && !File(uploadProgramPath).existsSync()) {
      _showErrorDialog('上传程序地址不是一个有效的 .py 文件');
      return;
    }

    // 如果所有路径都有效
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('所有路径有效')),
    );
    _saveSettings(); // 保存设置
  }

  void _validateDatabaseParameters() {
    // 这里可以添加具体的数据库参数校验逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('数据库参数校验')),
    );
    _saveSettings(); // 保存设置
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
                  Text('上传程序地址', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _uploadProgramPathController,
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
                          onPressed: () => _selectFile(_uploadProgramPathController),
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
                  Text('数据库参数', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    controller: _databasePasswordController,
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
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
        ],
      ),
    );
  }
}