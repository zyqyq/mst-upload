import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;
//import 'package:mysql_client/mysql_client.dart';

// 处理单个文件并插入数据库
Future<void> uploadL1B(String filePath, MySqlConnection conn, String showName,
    String name, String platformId) async {
  final data = await readAndProcessFile(filePath, showName, name, platformId);
  final fileName = path.basenameWithoutExtension(filePath);
  String tableName;

  if (fileName.endsWith('ST')) {
    tableName = 'smos_radar_qzgcz_L1BST';
  } else if (fileName.endsWith('ST_processed')) {
    tableName = 'smos_radar_qzgcz_L1BSTProcessed';
  } else if (fileName.endsWith('M')) {
    tableName = 'smos_radar_qzgcz_L1BM';
  } else if (fileName.endsWith('M_processed')) {
    tableName = 'smos_radar_qzgcz_L1BMProcessed';
  } else {
    throw Exception('Unsupported file type');
  }

  await insertDataToDatabase(conn, data, tableName); // 修改: 传递表名参数
}

// 读取并处理文件内容
Future<Map<String, dynamic>> readAndProcessFile(
    String filePath, String showName, String name, String platformId) async {
  final file = File(filePath);
  final lines = await file.readAsLines();
  final data = <String, dynamic>{};
  data['showName'] = showName;
  data['name'] = name;
  data['platformId'] = platformId;
  data['records'] = <Map<String, dynamic>>[];

  // 提取时间信息
  final fileName = path.basename(filePath);
  final dateTimeStr = fileName.split('_')[5]; // 修改: 提取正确的日期时间部分
  final dt = DateTime.parse('${dateTimeStr.substring(0, 4)}-${dateTimeStr.substring(4, 6)}-${dateTimeStr.substring(6, 8)}T${dateTimeStr.substring(8, 10)}:${dateTimeStr.substring(10, 12)}:${dateTimeStr.substring(12, 14)}');
  final dtStr = dt.toIso8601String();
  print("正在处理:$fileName");

  // 跳过前34行
  for (int i = 34; i < lines.length; i++) {
    final parts = lines[i].trim().split(RegExp(r'\s+'));
    if (parts.length < 15) continue;

    final height = _parseDouble(parts[0]);
    final snr1 = _parseDouble(parts[1]);
    final rv1 = _parseDouble(parts[2]);
    final sw1 = _parseDouble(parts[3]);
    final snr2 = _parseDouble(parts[4]);
    final rv2 = _parseDouble(parts[5]);
    final sw2 = _parseDouble(parts[6]);
    final snr3 = _parseDouble(parts[7]);
    final rv3 = _parseDouble(parts[8]);
    final sw3 = _parseDouble(parts[9]);
    final snr4 = _parseDouble(parts[10]);
    final rv4 = _parseDouble(parts[11]);
    final sw4 = _parseDouble(parts[12]);
    final snr5 = _parseDouble(parts[13]);
    final rv5 = _parseDouble(parts[14]);
    final sw5 = _parseDouble(parts[15]);


    // 添加记录
    data['records'].add({
      'Time': dtStr,
      'Height': height,
      'SNR1': snr1,
      'Rv1': rv1,
      'SW1': sw1,
      'SNR2': snr2,
      'Rv2': rv2,
      'SW2': sw2,
      'SNR3': snr3,
      'Rv3': rv3,
      'SW3': sw3,
      'SNR4': snr4,
      'Rv4': rv4,
      'SW4': sw4,
      'SNR5': snr5,
      'Rv5': rv5,
      'SW5': sw5,
    });
  }
  return data;
}

double _parseDouble(String str) {
  if (str.toLowerCase() == 'nan') {
    return -9999999; // 或者其他你认为合适的默认值
  }
  return double.parse(str);
}

// 插入数据到数据库
Future<void> insertDataToDatabase(
    MySqlConnection conn, Map<String, dynamic> data, String tableName) async {
  final insertSql = '''
  INSERT INTO $tableName (Time, show_name, name, Platform_id, Height, SNR1, Rv1, SW1, SNR2, Rv2, SW2, SNR3, Rv3, SW3, SNR4, Rv4, SW4, SNR5, Rv5, SW5)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''';
  for (final record in data['records']) {
    await conn.query(insertSql, [
      record['Time'],
      data['showName'],
      data['name'],
      data['platformId'],
      record['Height'],
      record['SNR1'],
      record['Rv1'],
      record['SW1'],
      record['SNR2'],
      record['Rv2'],
      record['SW2'],
      record['SNR3'],
      record['Rv3'],
      record['SW3'],
      record['SNR4'],
      record['Rv4'],
      record['SW4'],
      record['SNR5'],
      record['Rv5'],
      record['SW5'],
    ]);
  }
}
