import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path; // 添加路径处理库
import 'dart:convert'; // 添加json处理库

class TransferPage extends StatelessWidget {
  // 读取 setting.json 文件
  Future<Map<String, dynamic>> _readSettings() async {
    final settingsFile = File('settings.json');
    final settingsContent = await settingsFile.readAsString();
    return json.decode(settingsContent);
  }

  // 遍历文件夹并处理数据
  void processFiles() async {
    // 读取设置
    final settings = await _readSettings();
    final showName = settings['show_name'];
    final name = settings['name'];
    final platformId = settings['Platform_id'];

    // 定义数据库连接参数
    final dbParams = ConnectionSettings(
      host: '127.0.0.1',
      port: 3306,
      user: 'root',
      password: 'mysecretpw',
      db: 'joyaiot_monitor',
    );

    // 定义需要读取的文件夹路径
    final folderPath = '/Users/zyqyq/Program/数据集/L2BP/202408';

    // 记录程序开始时间
    final startTime = DateTime.now();

    // 链接MySQL
    final conn = await MySqlConnection.connect(dbParams);

    // 遍历文件夹
    final files = await Directory(folderPath).list().toList();
    for (final file in files) {
      if (file is Directory) {
        final subFiles = await file.list().toList();
        for (final subFile in subFiles) {
          if (subFile.path.endsWith('.TXT')) {
            final filePath = subFile.path;
            // 检查是否重复
            final isDuplicate =
                await _isDuplicateRecord(conn, filePath, name, platformId);
            if (isDuplicate) {
              print('记录已存在，跳过文件: $filePath');
              continue;
            }
            final data =
                await readAndProcessFile(filePath, showName, name, platformId);
            await insertDataToDatabase(conn, data);
          }
        }
      }
    }

    // 关闭游标和连接
    await conn.close();

    // 记录程序结束时间
    final endTime = DateTime.now();

    // 计算并打印程序运行时间
    final runTime = endTime.difference(startTime).inSeconds;
    print('所有文件处理完成，程序运行时间：$runTime秒');
  }

  // 检查是否重复记录
  Future<bool> _isDuplicateRecord(MySqlConnection conn, String filePath,
      String name, String platformId) async {
    final fileName = path.basename(filePath); // 使用path.basename获取文件名
    final dateTimeStr = fileName.split('_')[5];
    final dt = DateTime.parse(
        '${dateTimeStr.substring(0, 4)}-${dateTimeStr.substring(4, 6)}-${dateTimeStr.substring(6, 8)} ${dateTimeStr.substring(8, 10)}:${dateTimeStr.substring(10, 12)}:${dateTimeStr.substring(12)}');
    final dtStr = dt.toIso8601String();

    final MSTStr = fileName.split('_')[5];
    final MST = MSTStr == 'M' ? 0 : 1;

    final checkSql = '''
      SELECT COUNT(*) 
      FROM smos_radar_qzgcz_device2 
      WHERE Time = ? 
        AND name = ? 
        AND MST = ? 
        AND Platform_id = ?
    ''';
    final checkResult = await conn.query(checkSql, [
      dtStr,
      name,
      MST,
      platformId,
    ]);

    // 检查是否存在相同的记录
    final count = checkResult.first[0] as int? ?? 0; // 确保不会出现 null
    return count > 0;
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
    print("a $quantitative_indicators");
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
      MySqlConnection conn, Map<String, dynamic> data) async {
    final sql = '''
      INSERT INTO smos_radar_qzgcz_device2 
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

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: processFiles,
        child: Text('传输页面'),
      ),
    );
  }
}
