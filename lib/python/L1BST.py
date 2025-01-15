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

# 定义需要读取的文件夹路径
folder_path = "C:\\Users\\HUAWEI\\Desktop\\L1B" # 请替换为你的文件夹路径

# 记录程序开始时间
start_time = datetime.now()

# 链接MySQL
conn = pymysql.connect(**db_params)

# 创建游标对象
cursor2 = conn.cursor()

# 遍历文件夹
for filename1 in os.listdir(folder_path):
    for filename2 in os.listdir(os.path.join(folder_path, filename1)):
        if filename2.endswith('ST.TXT'):
            
            file_path = os.path.join(os.path.join(folder_path, filename1), filename2)
            
            date_time_str = filename2.split('_')[-3].split('.')[0]
            dt = datetime.strptime(date_time_str, '%Y%m%d%H%M%S')
            dt_str = dt.strftime('%Y-%m-%d %H:%M:%S') 

            with open(file_path, 'r') as file:
                for i in range(34):
                    next(file)  
                for line in file:
                    parts = line.strip().split()

                    height=float(parts[0])
                    SNR1=float(parts[1])
                    Rv1=float(parts[2])
                    SW1=float(parts[3])
                    SNR2=float(parts[4])
                    Rv2=float(parts[5])
                    SW2=float(parts[6])
                    SNR3=float(parts[7])
                    Rv3=float(parts[8])
                    SW3=float(parts[9])
                    SNR4=float(parts[10])
                    Rv4=float(parts[11])
                    SW4=float(parts[12])
                    SNR5=float(parts[13])
                    Rv5=float(parts[14])
                    SW5=float(parts[15])

                    if math.isnan(Rv1):
                        Rv1 = -9999999
                    if math.isnan(Rv2):
                        Rv2 = -9999999
                    if math.isnan(Rv3):
                        Rv3 = -9999999
                    if math.isnan(Rv4):
                        Rv4 = -9999999
                    if math.isnan(Rv5):
                        Rv5 = -9999999

                    sql = "INSERT INTO smos_radar_qzgcz_L1BST (Time, show_name ,name, Platform_id, Height, SNR1, Rv1, SW1, SNR2, Rv2, SW2, SNR3, Rv3, SW3, SNR4, Rv4, SW4, SNR5, Rv5, SW5) VALUES (%s, %s, %s, %s,%s,%s, %s, %s, %s, %s, %s, %s, %s,%s, %s,%s, %s, %s, %s, %s)"
                    cursor2.execute(sql, (dt_str,'MST雷达','qzgczMST','qzgcz',height, SNR1, Rv1, SW1, SNR2, Rv2, SW2, SNR3, Rv3, SW3, SNR4, Rv4, SW4, SNR5, Rv5, SW5))

            conn.commit()

# 关闭游标和连接
cursor2.close()
conn.close()

# 记录程序结束时间
end_time = datetime.now()

# 计算并打印程序运行时间
run_time = (end_time - start_time).total_seconds()
print(f"所有文件处理完成，程序运行时间：{run_time}秒")
