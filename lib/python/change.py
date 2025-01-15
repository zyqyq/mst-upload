import os
import re
import math
import numpy as np
from datetime import datetime

file_path = r"/Users/zyqyq/Program/数据集/L1BP/202408"
new_folder_path = r"/Users/zyqyq/Program/数据集/L2BP/202408"
# 记录程序开始时间
start_time = datetime.now()

for filename1 in os.listdir(file_path): 
    new_folder_full_path = os.path.join(new_folder_path, filename1)
    # 检查文件夹是否存在，如果不存在则创建
    if not os.path.exists(new_folder_full_path):
        os.makedirs(new_folder_full_path)  # 使用 os.makedirs 创建所有必要的父目录
        print(f"文件夹 {new_folder_full_path} 创建成功。")
    else:
        print(f"文件夹 {new_folder_full_path} 已经存在，跳过创建。")
    # 检查是否为目录
    if os.path.isdir(os.path.join(file_path, filename1)):
        for filename2 in os.listdir(os.path.join(file_path, filename1)):
            if filename2.endswith('.TXT') or filename2.endswith('.txt'):  # 仅对txt文件处理
                filepath = os.path.join(os.path.join(file_path, filename1), filename2)

                with open(filepath, 'r') as fileID:
                    heights = []
                    u = []
                    v = []
                    w = []
                    Cn2 = []
                    Credi = []

                    new_filename = filename2.replace('PSPP_L1B', 'AWCN_L2')
                    # 创建输出文件
                    new_file_name = os.path.join(new_folder_full_path, new_filename)

                    # 构建新的文件路径
                    with open(new_file_name, 'w') as outputFileID:
                        # 读取文件前6行
                        fileContent1 = [fileID.readline() for _ in range(6)]

                        # 读取第七行并替换L1B为L2
                        line7 = fileID.readline()
                        line7 = line7.replace('L1B', 'L2')

                        fileContent2 = [fileID.readline() for _ in range(8)]

                        # 写入文件前32行到输出文件
                        outputFileID.write('#DataName: Atmospheric Wind and Refractive Index Structure Constant\n')
                        for i in range(1, 6):
                            outputFileID.write(fileContent1[i])
                        outputFileID.write(line7)
                        for i in range(0, 8):
                            outputFileID.write(fileContent2[i])
                        outputFileID.write('#Height(km): The Height Level of the Wind Data, F7.2, missingdata=NaN\n')
                        outputFileID.write('#Horiz WS(m/s): Horizontal Wind Speed in m/s, F8.2, missingdata=-99999999\n')
                        outputFileID.write('#Horiz_WD(m/s): Horizontal Direction in Degree, Clockwise from Due North, F8.2, missingdata=-99999999\n')
                        outputFileID.write('#Verti_V(m/s): Vertical Velocity in m/s, F7.2, missingdata=-9999999\n')
                        outputFileID.write('#Cn2(dB): Atmospheric Refractive index Structure Constant in dB, F7.2, missingdata=-9999999\n')
                        outputFileID.write('#Credi: Credibility of Data, I5.3, missingdata=-99999\n')
                        outputFileID.write('#-------------------------------------------------------------------\n')

                        # 读取数据直到文件结束
                        for line in fileID:
                            if line.strip() and not line.startswith(('#', '%')):
                                line = line.replace('#', '').replace('%', '').strip()
                                data = line.split()
                                if len(data) >= 11:
                                    try:
                                        height = float(data[0])
                                        rv1 = float(data[2])
                                        rv2 = float(data[5])
                                        rv3 = float(data[8])
                                        rv4 = float(data[11])
                                        rv5 = float(data[14])

                                        if math.isnan(height):
                                            height = np.nan
                                        if math.isnan(rv1):
                                            rv1 = np.nan
                                        if math.isnan(rv2):
                                            rv2 = np.nan
                                        if math.isnan(rv3):
                                            rv3 = np.nan
                                        if math.isnan(rv4):
                                            rv4 = np.nan
                                        if math.isnan(rv5):
                                            rv5 = np.nan

                                        heights.append(height)
                                        u.append(abs((rv1 - rv2) / 2 / math.sin(math.radians(15))))
                                        v.append(abs((rv4 - rv3) / 2 / math.sin(math.radians(15))))
                                        w.append(rv5)
                                        ss = math.sqrt(u[-1]**2 + v[-1]**2)  # 风速
                                        sd = 2 * math.pi - math.atan2(u[-1], v[-1])  # 风向
                                        sd_degrees = math.degrees(sd)

                                        Cn2.append(-142.39)  # 假设Cn2的值是固定的
                                        Credi.append(100)  # 假设Credi的值是固定的

                                    except:
                                        continue

                        # 写入处理后的数据到输出文件
                        outputFileID.write('   Height    Horiz_WS    Horiz_WD    Verti_V     Cn2      Credi\n')
                        for i in range(len(heights)):
                            # 使用numpy的tostring方法来处理可能的nan值
                            outputFileID.write(f'    {heights[i]:.2f}    ')
                            outputFileID.write(f'{u[i]:.2f}    ')
                            outputFileID.write(f'{v[i]:.2f}    ')
                            outputFileID.write(f'{w[i]:.2f}    ')
                            outputFileID.write(f'{Cn2[i]:.2f}    ')
                            outputFileID.write(f'{Credi[i]:d}\n')

end_time = datetime.now()

# 计算并打印程序运行时间
run_time = (end_time - start_time).total_seconds()
print(f"所有文件处理完成，程序运行时间：{run_time}秒")