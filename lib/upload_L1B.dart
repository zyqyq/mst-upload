import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;
//import 'package:mysql_client/mysql_client.dart';

// 处理单个文件并插入数据库
Future<void> uploadL1B(String filePath, MySqlConnection conn, String showName,
    String name, String platformId) async {
  final data = await readAndProcessFile(filePath, showName, name, platformId);
  await insertDataToDatabase(conn, data); // 修改: 使用连接池
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

  // 跳过前34行
  for (int i = 34; i < lines.length; i++) {
    final parts = lines[i].trim().split(RegExp(r'\s+'));
    if (parts.length < 15) continue;

    final height = double.parse(parts[0]);
    final snr1 = double.parse(parts[1]);
    var rv1 = double.parse(parts[2]);
    final sw1 = double.parse(parts[3]);
    final snr2 = double.parse(parts[4]);
    var rv2 = double.parse(parts[5]);
    final sw2 = double.parse(parts[6]);
    final snr3 = double.parse(parts[7]);
    var rv3 = double.parse(parts[8]);
    final sw3 = double.parse(parts[9]);
    final snr4 = double.parse(parts[10]);
    var rv4 = double.parse(parts[11]);
    final sw4 = double.parse(parts[12]);
    final snr5 = double.parse(parts[13]);
    var rv5 = double.parse(parts[14]);
    final sw5 = double.parse(parts[15]);

    // 处理NaN值
    if (rv1.isNaN) rv1 = -9999999;
    if (rv2.isNaN) rv2 = -9999999;
    if (rv3.isNaN) rv3 = -9999999;
    if (rv4.isNaN) rv4 = -9999999;
    if (rv5.isNaN) rv5 = -9999999;

    // 提取时间信息
    final fileName = path.basename(filePath);
    print(fileName);
    final dateTimeStr = fileName.split('_')[5]; // 修改: 提取正确的日期时间部分
    final dt = DateTime.parse('${dateTimeStr.substring(0, 4)}-${dateTimeStr.substring(4, 6)}-${dateTimeStr.substring(6, 8)}T${dateTimeStr.substring(8, 10)}:${dateTimeStr.substring(10, 12)}:${dateTimeStr.substring(12, 14)}');
    final dtStr = dt.toIso8601String();
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

// 插入数据到数据库
Future<void> insertDataToDatabase(
    MySqlConnection conn, Map<String, dynamic> data) async {
  final insertSql = '''
  INSERT INTO smos_radar_qzgcz_L1BM (Time, showname, name, Platform_id, Height, SNR1, Rv1, SW1, SNR2, Rv2, SW2, SNR3, Rv3, SW3, SNR4, Rv4, SW4, SNR5, Rv5, SW5)
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
