import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // 添加文件选择器库
import 'dart:io'; // 添加dart:io库以使用Directory和File类
import 'dart:convert'; // 添加dart:convert库以使用json.decode和json.encode
import 'package:mysql1/mysql1.dart'; // 添加 mysql1 库以进行数据库连接

class TransferPage extends StatefulWidget {
  @override
  _TransferPageState createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  Future<void> _selectAndUploadFiles() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['TXT']);
    if (result != null && result.files.isNotEmpty) {
      final files = result.files;
      for (final file in files) {
        final filePath = file.path!;
        final fileName = file.name;
        await _uploadFile(filePath, fileName);
      }
    }
  }

  Future<void> _uploadFile(String filePath, String fileName) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件不存在')),
      );
      return;
    }

    final settingsFile = File('settings.json');
    if (!await settingsFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置文件不存在')),
      );
      return;
    }

    final settingsContents = await settingsFile.readAsString();
    final settings = json.decode(settingsContents);

    final dbParams = {
      'host': settings['databaseAddress'],
      'port': int.tryParse(settings['databasePort']) ?? 3306,
      'user': settings['databaseUsername'],
      'password': settings['databasePassword'],
      'db': settings['databaseName'],
      'charset': 'utf8'
    };

    final conn = await MySqlConnection.connect(ConnectionSettings(
      host: dbParams['host'],
      port: dbParams['port'],
      user: dbParams['user'],
      password: dbParams['password'],
      db: dbParams['db'],
    ));

    final date_time_str = fileName.split('_')[-4].split('.')[0];
    final dt = DateTime.parse(date_time_str);
    final dt_str = dt.toIso8601String().split('T')[0] + ' ' + dt.toIso8601String().split('T')[1].split('.')[0];

    final MSTstr = fileName.split('_')[-2].split('.')[0];
    final MST = MSTstr == 'M' ? 0 : 1;

    final lines = await file.readAsLines();
    String? QualityFlag;
    List<String>? quantitative_indicators;
    List<String>? device_state;
    List<String>? device_spec;
    List<String>? obs_parameters;

    for (final line in lines) {
      if (line.startsWith('#QualityFlag:')) {
        QualityFlag = RegExp(r'(\d+)').firstMatch(line)?.group(1);
      } else if (line.startsWith('#quantitative indicators:')) {
        quantitative_indicators = line.split(' ').skip(2).toList();
      } else if (line.startsWith('#DeviceState:')) {
        device_state = RegExp(r'(\d+)').allMatches(line).map((m) => m.group(0)!).toList();
      } else if (line.startsWith('#DeviceSpec:')) {
        device_spec = RegExp(r'(\d+\.\d+|\d+)').allMatches(line).map((m) => m.group(0)!).toList();
      } else if (line.startsWith('#ObsParameters:')) {
        obs_parameters = RegExp(r'(\d+\.\d+|\d+)').allMatches(line).map((m) => m.group(0)!).toList();
      }
    }

    if (QualityFlag != null && quantitative_indicators != null && device_state != null && device_spec != null && obs_parameters != null) {
      final RecordNumber = int.parse(quantitative_indicators[0]);
      final RecordNumProcessed = int.parse(quantitative_indicators[1]);
      final Lof_delete_dot = int.parse(quantitative_indicators[2]);
      final Seconded_delete_dot = int.parse(quantitative_indicators[3]);
      final Prefactor = double.parse(quantitative_indicators[4]);
      final Aftfactor = double.parse(quantitative_indicators[5]);

      final TansInputPower = int.parse(device_state[0]);
      final WellRAntennaNum = int.parse(device_state[1]);
      final WellTAntennaNum = int.parse(device_state[2]);

      final Freq = double.parse(device_spec[0]);
      final PkPower = int.parse(device_spec[1]);
      final RAntennaNum = int.parse(device_spec[2]);
      final TAntennaNum = int.parse(device_spec[3]);
      final BeamWidth = double.parse(device_spec[4]);
      final Rband = double.parse(device_spec[5]);

      final PlsWidth = double.parse(obs_parameters[0]);
      final PlsCode = int.parse(obs_parameters[1]);
      final PRF = double.parse(obs_parameters[2]);
      final PlsAccum = int.parse(obs_parameters[3]);
      final Range = int.parse(obs_parameters[4]);
      final GateNum = int.parse(obs_parameters[5]);
      final Rmin = int.parse(obs_parameters[6]);
      final EleAngle = double.parse(obs_parameters[7]);
      final nFFT = int.parse(obs_parameters[8]);
      final SpAverage = int.parse(obs_parameters[9]);

      final sql = "INSERT INTO smos_radar_qzgcz_device2 (Time, show_name, name, MST, Platform_id, RecordNumber, RecordNumProcessed, Lof_delete_dot, Seconded_delete_dot, Prefactor, Aftfactor, QualityFlag, TansInputPower, WellRAntennaNum, WellTAntennaNum, Freq, PkPower, RAntennaNum, TAntennaNum, BeamWidth, Rband, PlsWidth, PlsCode, PRF, PlsAccum, Ranges, GateNum, Rmin, EleAngle, BeamOrder, nFFT, SpAverage) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
      await conn.query(sql, [
        dt_str,
        'MST雷达',
        'qzgczMST',
        MST,
        'qzgcz',
        RecordNumber,
        RecordNumProcessed,
        Lof_delete_dot,
        Seconded_delete_dot,
        Prefactor,
        Aftfactor,
        int.parse(QualityFlag),
        TansInputPower,
        WellRAntennaNum,
        WellTAntennaNum,
        Freq,
        PkPower,
        RAntennaNum,
        TAntennaNum,
        BeamWidth,
        Rband,
        PlsWidth,
        PlsCode,
        PRF,
        PlsAccum,
        Range,
        GateNum,
        Rmin,
        EleAngle,
        "SZNEW",
        nFFT,
        SpAverage
      ]);
    }

    await conn.close();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('文件上传成功')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('传输页面'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _selectAndUploadFiles,
          child: Text('选择并上传文件'),
        ),
      ),
    );
  }
}