import 'dart:io';
import 'dart:convert';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as path;

double _parseDouble(String str) {
  if (str.toLowerCase() == 'nan') {
    return -9999999; // 或者其他你认为合适的默认值
  }
  return double.parse(str);
}

Future<void> uploadL2(String newFilePath2, MySqlConnection conn, String showName, String name, String platformId) async {

  final fileName = path.basenameWithoutExtension(newFilePath2);
  String tableName;

  if (fileName.endsWith('ST')) {
    tableName = 'smos_radar_qzgcz_L2ST';
  } else if (fileName.endsWith('ST_processed')) {
    tableName = 'smos_radar_qzgcz_L2STProcessed';
  } else if (fileName.endsWith('M')) {
    tableName = 'smos_radar_qzgcz_L2M';
  } else if (fileName.endsWith('M_processed')) {
    tableName = 'smos_radar_qzgcz_L2MProcessed';
  } else {
    throw Exception('Unsupported file type');
  }

  // 读取文件
  final file = File(newFilePath2);
  final lines = await file.readAsLines();

  // 跳过前23行
  final dataLines = lines.sublist(23);

  for (var line in dataLines) {
    final parts = line.trim().split(RegExp(r'\s+'));

    final height = _parseDouble(parts[0]);
    final horiz_ws = _parseDouble(parts[1]);
    final horiz_wd = _parseDouble(parts[2]);
    final verti_v = _parseDouble(parts[3]);
    final Cn2 = _parseDouble(parts[4]);
    final Credi = _parseDouble(parts[5]);

    // 解析文件名中的日期时间
    final fileName = path.basename(newFilePath2);
    final dateTimeStr = fileName.split('_')[5]; // 修改: 提取正确的日期时间部分
    final dt = DateTime.parse('${dateTimeStr.substring(0, 4)}-${dateTimeStr.substring(4, 6)}-${dateTimeStr.substring(6, 8)}T${dateTimeStr.substring(8, 10)}:${dateTimeStr.substring(10, 12)}:${dateTimeStr.substring(12, 14)}');
    final dtStr = dt.toIso8601String();

    // 执行 SQL 语句
    await conn.query(
      'INSERT INTO $tableName (Time,show_name,name,Platform_id, Height, Horiz_WS, Horiz_WD, Verti_V, Cn2, Credi) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [dtStr, showName, name, platformId, height, horiz_ws, horiz_wd, verti_v, Cn2, Credi],
    );
  }

}