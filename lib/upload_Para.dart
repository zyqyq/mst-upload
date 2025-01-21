import 'dart:convert';
import 'dart:io';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;

Future<void> uploadPara(String filePath, MySqlConnection conn,
    String showName, String name, String platformId,String set) async {
    // 读取并处理文件
    final data = await readAndProcessFile(filePath, showName, name, platformId);
    // 插入数据到数据库
    await insertDataToDatabase(conn, data,set);
    }

// 读取并处理文件
Future<Map<String, dynamic>> readAndProcessFile(
    String filePath, String showName, String name, String platformId) async {
  final file = File(filePath);
  final lines = await file.readAsLines();
  final data = <String, dynamic>{};

  // 读取文件内容
  String? QualityFlag;
  List<String>? quantitative_indicators;
  List<String>? device_state;
  List<String>? device_spec;
  List<String>? obs_parameters;

  for (final line in lines) {
    if (line.startsWith('#QualityFlag:')) {
      QualityFlag = RegExp(r'(\d+)').firstMatch(line)?.group(1);
    } else if (line.startsWith('#quantitative indicators:')) {
      // 修改: 使用正则表达式处理连续多个空格
      quantitative_indicators = line.split(RegExp(r'\s+')).skip(2).toList();
    } else if (line.startsWith('#DeviceState:')) {
      device_state = RegExp(r'(\d+)')
          .allMatches(line)
          .map((match) => match.group(1)!)
          .toList();
    } else if (line.startsWith('#DeviceSpec:')) {
      device_spec = RegExp(r'(\d+\.\d+|\d+)')
          .allMatches(line)
          .map((match) => match.group(0)!)
          .toList();
    } else if (line.startsWith('#ObsParameters:')) {
      obs_parameters = RegExp(r'(\d+\.\d+|\d+)')
          .allMatches(line)
          .map((match) => match.group(0)!)
          .toList();
    }
  }

  // 检查是否所有变量都已正确赋值
  if (QualityFlag == null ||
      quantitative_indicators == null ||
      device_state == null ||
      device_spec == null ||
      obs_parameters == null) {
    throw Exception('文件内容不完整，缺少必要的注释行');
  }

  // 添加对 QualityFlag 的有效性检查
  if (!RegExp(r'^\d+$').hasMatch(QualityFlag)) {
    throw FormatException('QualityFlag 不是一个有效的整数');
  }
  //print("a $quantitative_indicators");
  // 添加对 quantitative_indicators[0] 的有效性检查
  if (!RegExp(r'^\d+$').hasMatch(quantitative_indicators[0])) {
    throw FormatException('quantitative_indicators[0] 不是一个有效的整数');
  }

  // 提取定量指标
  data['QualityFlag'] = int.parse(QualityFlag);
  data['RecordNumber'] = int.parse(quantitative_indicators[0]);
  data['RecordNumProcessed'] = int.parse(quantitative_indicators[1]);
  data['Lof_delete_dot'] = int.parse(quantitative_indicators[2]);
  data['Seconded_delete_dot'] = int.parse(quantitative_indicators[3]);
  data['Prefactor'] = double.parse(quantitative_indicators[4]);
  data['Aftfactor'] = double.parse(quantitative_indicators[5]);

  // 提取设备状态
  data['TansInputPower'] = int.parse(device_state[0]);
  data['WellRAntennaNum'] = int.parse(device_state[1]);
  data['WellTAntennaNum'] = int.parse(device_state[2]);

  // 提取设备规格
  data['Freq'] = double.parse(device_spec[0]);
  data['PkPower'] = int.parse(device_spec[1]);
  data['RAntennaNum'] = int.parse(device_spec[2]);
  data['TAntennaNum'] = int.parse(device_spec[3]);
  data['BeamWidth'] = double.parse(device_spec[4]);
  data['Rband'] = double.parse(device_spec[5]);

  // 提取观测参数
  data['PlsWidth'] = double.parse(obs_parameters[0]);
  data['PlsCode'] = int.parse(obs_parameters[1]);
  data['PRF'] = double.parse(obs_parameters[2]);
  data['PlsAccum'] = int.parse(obs_parameters[3]);
  data['Range'] = int.parse(obs_parameters[4]);
  data['GateNum'] = int.parse(obs_parameters[5]);
  data['Rmin'] = int.parse(obs_parameters[6]);
  data['EleAngle'] = double.parse(obs_parameters[7]);
  data['nFFT'] = int.parse(obs_parameters[8]);
  data['SpAverage'] = int.parse(obs_parameters[9]);

  // 提取时间
  final fileName = path.basename(file.path); // 使用path.basename获取文件名
  final dateTimeStr = fileName.split('_')[5];
  final dt = DateTime.parse(
      '${dateTimeStr.substring(0, 4)}-${dateTimeStr.substring(4, 6)}-${dateTimeStr.substring(6, 8)} ${dateTimeStr.substring(8, 10)}:${dateTimeStr.substring(10, 12)}:${dateTimeStr.substring(12)}');
  data['Time'] = dt.toIso8601String();

  // 提取MST
  final MSTStr = fileName.split('_')[5];
  data['MST'] = MSTStr == 'M' ? 0 : 1;

  // 添加 show_name 和 Platform_id
  data['show_name'] = showName;
  data['Platform_id'] = platformId;

  return data;
}

// 插入数据到数据库
Future<void> insertDataToDatabase(
    MySqlConnection conn, Map<String, dynamic> data,String set) async {
  final sql = '''
    INSERT INTO $set 
    (Time, show_name, name, MST, Platform_id, RecordNumber, RecordNumProcessed, Lof_delete_dot, Seconded_delete_dot, Prefactor, Aftfactor, QualityFlag, TansInputPower, WellRAntennaNum, WellTAntennaNum, Freq, PkPower, RAntennaNum, TAntennaNum, BeamWidth, Rband, PlsWidth, PlsCode, PRF, PlsAccum, Ranges, GateNum, Rmin, EleAngle, BeamOrder, nFFT, SpAverage) 
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''';
  await conn.query(sql, [
    data['Time'],
    data['show_name'],
    data['name'],
    data['MST'],
    data['Platform_id'],
    data['RecordNumber'],
    data['RecordNumProcessed'],
    data['Lof_delete_dot'],
    data['Seconded_delete_dot'],
    data['Prefactor'],
    data['Aftfactor'],
    data['QualityFlag'],
    data['TansInputPower'],
    data['WellRAntennaNum'],
    data['WellTAntennaNum'],
    data['Freq'],
    data['PkPower'],
    data['RAntennaNum'],
    data['TAntennaNum'],
    data['BeamWidth'],
    data['Rband'],
    data['PlsWidth'],
    data['PlsCode'],
    data['PRF'],
    data['PlsAccum'],
    data['Range'], // 修改: 修正列名 'Ranges' 为 'Range'
    data['GateNum'],
    data['Rmin'],
    data['EleAngle'],
    'SZNEW',
    data['nFFT'],
    data['SpAverage']
  ]);
}
