import os
import pymysql
import csv
from datetime import datetime

# 定义数据库连接参数
db_params = {
    'host': '47.108.142.190',
    'port': 3306,
    'user': 'root',
    'password': 'ynhn@1234',
    'db': 'joyaiot_monitor',
    'charset': 'utf8'
}

# 定义需要读取的文件夹路径L
folder_path = "C:\\Users\\HUAWEI\\Desktop\\L2A" # 请替换为你的文件夹路径

# 记录程序开始时间
start_time = datetime.now()
# 链接MySQL
conn = pymysql.connect(**db_params)

# 创建游标对象
cursor2 = conn.cursor()

# 遍历文件夹
for filename1 in os.listdir(folder_path):
    for filename2 in os.listdir(os.path.join(folder_path, filename1)):
        if filename2.endswith('M.TXT'):   
            file_path = os.path.join(os.path.join(folder_path, filename1), filename2)
            
            date_time_str = filename2.split('_')[-3].split('.')[0]

            dt = datetime.strptime(date_time_str, '%Y%m%d%H%M%S')
            dt_str = dt.strftime('%Y-%m-%d %H:%M:%S') 

            with open(file_path, 'r') as file:
                for i in range(23):
                    next(file)  
                for line in file:
                    parts = line.strip().split()
                    
                    height = float(parts[0])
                    horiz_ws = float(parts[1])
                    horiz_wd = float(parts[2])
                    verti_v = float(parts[3])
                    Cn2=float(parts[4])
                    Credi=float(parts[5])
                    
        
                    # 执行 SQL 语句
                    sql = "INSERT INTO smos_radar_qzgcz_L2M(Time,show_name,name,Platform_id, Height, Horiz_WS, Horiz_WD, Verti_V, Cn2, Credi) VALUES (%s,%s,%s,%s, %s, %s, %s, %s, %s, %s)"
                    cursor2.execute(sql, (dt_str,'MST雷达','qzgczMST','qzgcz', height, horiz_ws, horiz_wd, verti_v,Cn2, Credi))

            conn.commit()

# 关闭游标和连接
cursor2.close()
conn.close()

# 记录程序结束时间
end_time = datetime.now()

# 计算并打印程序运行时间
run_time = (end_time - start_time).total_seconds()
print(f"所有文件处理完成，程序运行时间：{run_time}秒")
