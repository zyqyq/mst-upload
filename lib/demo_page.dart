import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class DemoPage extends StatefulWidget {
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  const DemoPage({Key? key, this.onEnter, this.onExit}) : super(key: key);

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.onEnter?.call();
  }

  @override
  void dispose() {
    widget.onExit?.call();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _controller.text = result.files.single.path!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('演示')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: '文件路径',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _pickFile,
                  child: Text('浏览'),
                ),
              ],
            ),
            // ... 可继续添加演示内容 ...
          ],
        ),
      ),
    );
  }
}
