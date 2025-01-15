import os
import pymysql
import csv
from datetime import datetime
import math

# 定义数据库连接参数
db_params = {
    'host': '47.108.142.190',
    'port': 3306,
    'user': 'root',
    'password': 'ynhn@1234',
    'db': 'joyaiot_monitor',
    'charset': 'utf8'
}


# 记录程序开始时间
start_time = datetime.now()
# 链接MySQL
conn = pymysql.connect(**db_params)

# 创建游标对象
cursor2 = conn.cursor()

 # 执行 SQL 语句
sql = "UPDATE smos_radar_qzgcz_L2MProcessed SET show_name = %s"
new_show_name1 = 'MST雷达'
cursor2.execute(sql, (new_show_name1,))


sql = "UPDATE smos_radar_qzgcz_L2MProcessed SET name = %s"
new_show_name2 = 'qzgczMST'
cursor2.execute(sql, (new_show_name2,))

conn.commit()

# 关闭游标和连接
cursor2.close()
conn.close()

# 记录程序结束时间
end_time = datetime.now()

# 计算并打印程序运行时间
run_time = (end_time - start_time).total_seconds()
print(f"所有文件处理完成，程序运行时间：{run_time}秒")
