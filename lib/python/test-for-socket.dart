import 'dart:async';
import 'package:mysql1/mysql1.dart';
import 'dart:io';

/// 数据库连接验证函数
Future<bool> validateDatabaseConnection(ConnectionSettings dbParams) async {
  try {
      final socket = await Socket.connect(dbParams.host, dbParams.port);
      print('基础 TCP 连接成功');
      socket.destroy();
    } catch (e) {
      print('网络层连接失败: $e');
    }
  MySqlConnection? conn;
  try {
    // 尝试连接到数据库
    conn = await MySqlConnection.connect(dbParams).timeout(const Duration(seconds: 5));
    // 执行简单查询以验证连接有效性
    final result = await conn.query('SELECT 1');
    if (result.isNotEmpty) {
      print('数据库连接验证成功');
      return true;
    } else {
      print('数据库连接验证失败：查询结果为空');
      return false;
    }
  } catch (e, stackTrace) {
    // 捕获并打印连接失败的详细信息
    print('数据库连接失败: $e');
    print('堆栈信息: $stackTrace');
    return false;
  } finally {
    // 确保关闭数据库连接
    await conn?.close();
  }
}

/// 主函数：测试数据库连接
void main() async {
  // 配置数据库连接参数
  final dbParams = ConnectionSettings(
    host: '127.0.0.1', // 替换为实际数据库主机地址
    port: 3306, // 替换为实际数据库端口
    user: 'root', // 替换为实际用户名
    password: 'mysecretpw', // 替换为实际密码
    db: 'joyaiot_monitor', // 替换为实际数据库名称
    useSSL: true,
    ssl: SecurityContext.defaultContext,
  )
);

  // 验证数据库连接
  final isValid = await validateDatabaseConnection(dbParams);
  if (isValid) {
    print('数据库连接正常');
  } else {
    print('数据库连接异常，请检查配置');
  }
}