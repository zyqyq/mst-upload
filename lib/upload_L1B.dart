import 'dart:io';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;

// 处理单个文件并插入数据库
Future<void> uploadL1B(String filePath, MySqlConnection conn, String showName,
    String name, String platformId, Map<String, dynamic> settings) async {
  final data = await readAndProcessFile(filePath, showName, name, platformId);
  final fileName = path.basenameWithoutExtension(filePath);
  String tableName;

  if (fileName.endsWith('ST')) {
    tableName = settings['L1BSTTableName']; // 从设置中读取表名
  } else if (fileName.endsWith('ST_processed')) {
    tableName = settings['L1BSTProcessedTableName']; // 从设置中读取表名
  } else if (fileName.endsWith('M')) {
    tableName = settings['L1BMTableName']; // 从设置中读取表名
  } else if (fileName.endsWith('M_processed')) {
    tableName = settings['L1BMProcessedTableName']; // 从设置中读取表名
  } else {
    throw Exception('Unsupported file type');
  }

 try {
  await conn.query('SELECT 1');
} catch (e) {
  // 捕获异常并打印错误信息
  print('数据库连接测试失败: $e');
  rethrow; // 如果需要继续抛出异常，可以使用 rethrow
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
  final dateTimeStr = fileName.split('_')[5]; 
  final dt = DateTime.parse(
      '${dateTimeStr.substring(0, 4)}-${dateTimeStr.substring(4, 6)}-${dateTimeStr.substring(6, 8)}T${dateTimeStr.substring(8, 10)}:${dateTimeStr.substring(10, 12)}:${dateTimeStr.substring(12, 14)}');
  data['Time'] = dt.toIso8601String();
  //print("正在处理:$fileName");

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

  // 使用事务包裹所有插入操作
  await conn.transaction((transaction) async {
    final batch = <List<dynamic>>[];
    for (final record in data['records']) {
      batch.add([
        data['Time'],
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

      // 批量插入，每次最多插入 1000 条记录
      if (batch.length >= 1000) {
        await transaction.queryMulti(insertSql, batch);
        batch.clear();
      }
    }

    // 插入剩余的记录
    if (batch.isNotEmpty) {
      await transaction.queryMulti(insertSql, batch);
    }
  });
}