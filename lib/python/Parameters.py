import os
import pymysql
import csv
from datetime import datetime
import re

# 定义数据库连接参数
db_params = {
    'host': '127.0.0.1',
    'port': 3306,
    'user': 'root',
    'password': 'mysecretpw',
    'db': 'joyaiot_monitor',
    'charset': 'utf8'
}

# 定义需要读取的文件夹路径
folder_path = r"/Users/zyqyq/Program/数据集/L2/202408-L2" # 请替换为你的文件夹路径

# 记录程序开始时间
start_time = datetime.now()
# 链接MySQL
conn = pymysql.connect(**db_params)

# 创建游标对象
cursor2 = conn.cursor()

# 遍历文件夹
for filename1 in os.listdir(folder_path):
    for filename2 in os.listdir(os.path.join(folder_path, filename1)):  
        if filename2.endswith('.TXT'):
            file_path = os.path.join(os.path.join(folder_path, filename1), filename2)    
            date_time_str = filename2.split('_')[-4].split('.')[0]
            dt = datetime.strptime(date_time_str, '%Y%m%d%H%M%S')

            dt_str = dt.strftime('%Y-%m-%d %H:%M:%S') 

            MSTstr = date_time_str = filename2.split('_')[-2].split('.')[0]
            if MSTstr == 'M':
                MST = 0
            else:
                MST = 1

            with open(file_path, 'r') as file:
                 # 读取文件内容
                for line in file:
                    # 检查是否为特定注释行
                    if line.startswith('#QualityFlag:'):
                         QualityFlag = re.findall(r'(\d+)', line)
                    elif line.startswith('#quantitative indicators:'):
                        quantitative_indicators = line.split()[2:]
                    elif line.startswith('#DeviceState:'):
                        device_state = re.findall(r'(\d+)', line)
                    elif line.startswith('#DeviceSpec:'):
                        device_spec = re.findall(r'(\d+\.\d+|\d+)', line)
                    elif line.startswith('#ObsParameters:'):
                        obs_parameters = re.findall(r'(\d+\.\d+|\d+)', line)
        
                # 如果所有特定注释行都已读取，则处理文件
                if quantitative_indicators and device_state and device_spec and obs_parameters:
                                
                    QualityFlag = int(QualityFlag[0])

                    # 提取定量指标
                    RecordNumber = int(quantitative_indicators[0])
                    RecordNumProcessed = int(quantitative_indicators[1])
                    Lof_delete_dot = int(quantitative_indicators[2])
                    Seconded_delete_dot = int(quantitative_indicators[3])
                    Prefactor = float(quantitative_indicators[4])
                    Aftfactor = float(quantitative_indicators[5])

                    TansInputPower= int(device_state[0])
                    WellRAntennaNum = int(device_state[1])
                    WellTAntennaNum = int(device_state[2])

                    Freq = float(device_spec[0])
                    PkPower = int(device_spec[1])
                    RAntennaNum = int(device_spec[2])
                    TAntennaNum = int(device_spec[3])
                    BeamWidth = float(device_spec[4])
                    Rband = float(device_spec[5])

                    PlsWidth = float(obs_parameters[0])
                    PlsCode = int(obs_parameters[1])
                    PRF = float(obs_parameters[2])
                    PlsAccum = int(obs_parameters[3])
                    Range = int(obs_parameters[4])
                    GateNum = int(obs_parameters[5])
                    Rmin = int(obs_parameters[6])
                    EleAngle = float(obs_parameters[7])
                    nFFT = int(obs_parameters[8])
                    SpAverage = int(obs_parameters[9])

                    # 写入数据库
                    sql="INSERT INTO smos_radar_qzgcz_device2 (Time,show_name ,name, MST,Platform_id,RecordNumber, RecordNumProcessed, Lof_delete_dot,Seconded_delete_dot,Prefactor, Aftfactor,QualityFlag,TansInputPower, WellRAntennaNum, WellTAntennaNum, Freq,PkPower, RAntennaNum, TAntennaNum, BeamWidth,Rband, PlsWidth, PlsCode, PRF, PlsAccum, Ranges,GateNum, Rmin, EleAngle, BeamOrder, nFFT, SpAverage) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)"
                    cursor2.execute(sql, (dt_str,'MST雷达','qzgczMST',MST,"qzgcz" ,RecordNumber, RecordNumProcessed, Lof_delete_dot, Seconded_delete_dot,Prefactor, Aftfactor,QualityFlag,TansInputPower, WellRAntennaNum, WellTAntennaNum,Freq,PkPower, RAntennaNum, TAntennaNum, BeamWidth,Rband, PlsWidth, PlsCode, PRF, PlsAccum, Range,GateNum, Rmin, EleAngle, "SZNEW", nFFT, SpAverage))
conn.commit()

# 关闭游标和连接
cursor2.close()
conn.close()

# 记录程序结束时间
end_time = datetime.now()

# 计算并打印程序运行时间
run_time = (end_time - start_time).total_seconds()
print(f"所有文件处理完成，程序运行时间：{run_time}秒")
