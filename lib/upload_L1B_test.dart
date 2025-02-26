import 'dart:io';
import 'package:mysql1/mysql1.dart';
import 'upload_L1B.dart';

void main() async {
  // 数据库连接配置
  final settings = ConnectionSettings(
    host: '127.0.0.1',
    port: 3306,
    user: 'root',
    password: 'mysecretpw',
    db: 'joyaiot_monitor',
  );

  // 测试文件路径
  final testFilePath = '/Users/zyqyq/Program/数据集/L1B/202408/20240801/OQZQB_MSTR01_PSPP_L1B_30M_20240801180000_V01.00_ST.TXT';

  // 其他必要参数
  final showName = 'TestShow';
  final name = 'TestName';
  final platformId = 'TestPlatform';
  final settingsMap = {
    "L1BSTTableName": "smos_radar_qzgcz_L1BST",
  "L1BSTProcessedTableName": "smos_radar_qzgcz_L1BSTProcessed",
  "L1BMTableName": "smos_radar_qzgcz_L1BM",
  "L1BMProcessedTableName": "smos_radar_qzgcz_L1BMProcessed",
  };

  // 测试次数
  final testIterations = 20;

  // 初始化统计数据
  List<int> executionTimes = [];
  int totalTime = 0;
  int minTime = 999999999; // 初始值设为一个很大的数
  int maxTime = 0;

  // 建立数据库连接
  final conn = await MySqlConnection.connect(settings);

  try {
    for (int i = 0; i < testIterations; i++) {
      print('Running test iteration ${i + 1}...');

      // 开始计时
      final stopwatch = Stopwatch()..start();

      // 调用上传函数
      await uploadL1B(testFilePath, conn, showName, name, platformId, settingsMap);

      // 停止计时
      stopwatch.stop();
      final elapsedMilliseconds = stopwatch.elapsedMilliseconds;

      // 更新统计数据
      executionTimes.add(elapsedMilliseconds);
      totalTime += elapsedMilliseconds;
      if (elapsedMilliseconds < minTime) minTime = elapsedMilliseconds;
      if (elapsedMilliseconds > maxTime) maxTime = elapsedMilliseconds;

      print('Iteration ${i + 1} completed in ${elapsedMilliseconds}ms');
    }

    // 计算平均时间
    final averageTime = totalTime / testIterations;

    // 输出统计结果
    print('\n--- Test Results ---');
    print('Total iterations: $testIterations');
    print('Average execution time: ${averageTime.toStringAsFixed(2)}ms');
    print('Minimum execution time: ${minTime}ms');
    print('Maximum execution time: ${maxTime}ms');
  } finally {
    // 关闭数据库连接
    await conn.close();
  }
}