import numpy as np
from sklearn.neighbors import LocalOutlierFactor
from sklearn.cluster import DBSCAN
import math
import sys
import pandas as pd
#import matplotlib.pyplot as plt
import re
import os
from datetime import datetime

count10=0#原始数据
count0=0#去除3NaN后的数
count=0#记录LOF去除的点
count1=0#记录SECOND去除的点
prefactor=0#处理前有关对称度的参数，NaN不参与
aftfactor=0#处理后与对称度有关的参数，NaN不参与
def read_data(filename):
    """读取原始数据文件，并收集前33行的注释"""
    comments = []  # 存储注释行
    data = []      # 存储数据行
    with open(filename, 'r') as file:
        # 收集注释行
        for i in range(33):
            comment_line = next(file)
            comments.append(comment_line)

        # 读取数据
        for line in file:
            parts = line.strip().split()
            # 假设数据格式为 Height, SNR1, Rv1, ..., SW5
            data.append([float(part) if part != '-9999999' else np.nan for part in parts])
    return np.array(data), comments

def correct_low(data):
    #data= correct_LOF(data,threshold=a)
    data= correct_DBS(data,eps=1.7,min=8)
    data= correct_based_on_second_derivative(data, threshold=3)
    return data

def correct_high(data):
    #data= correct_LOF(data,threshold=a)
    data= correct_DBS(data,eps=2,min=5)
    # data= correct_iqr(data)
    return data
def factordetect(data):
    velocity_columns = [2, 5, 8, 11, 14]
    outlier_indices = {}
    # 移除包含三个及以上 NaN 值的行
    nan_count = np.sum(np.isnan(data), axis=1)
    cleaned_data = data
    sum = 0
    len1 = 0
    len2 = 0
    for i, (v1, v2) in enumerate(zip(cleaned_data[:,2], cleaned_data[:,5])):
        if not math.isnan(v1) and not math.isnan(v2):
            sum = sum + abs(abs(v1) - abs(v2)) ** 2
            len1 = len1 + 1
    for j, (v1, v2) in enumerate(zip(cleaned_data[:,8], cleaned_data[:,11])):
        if not math.isnan(v1) and not math.isnan(v2):
            sum = sum + abs(abs(v1) - abs(v2)) ** 2
            len2 = len2 + 1
    global prefactor
    prefactor = sum / (len1 + len2) if (len1 + len2) > 0 else -1

def correct_LOF(data,threshold=28):
    """校正数据并移除异常值"""
    # 假设速度列是第 3、6、9、12 和 15 列（从0开始计数）
    global count0
    velocity_columns = [2, 5, 8, 11, 14]
    outlier_indices = {}
    global count
    # 移除包含三个及以上 NaN 值的行
    nan_count = np.sum(np.isnan(data), axis=1)
    cleaned_data = data
    count0=len(cleaned_data[:,2])
    for col in velocity_columns:
        # 选择当前列并应用 LocalOutlierFactor
        X = cleaned_data[:, col].reshape(-1, 1)
        nan_mask = np.isnan(X).any(axis=1)
        X = X[~nan_mask]
        # 使用较小的 n_neighbors，以避免警告
        lof = LocalOutlierFactor(n_neighbors=min(len(X), threshold), contamination='auto')
        outlier_labels = lof.fit_predict(X)
        # 找出异常值的索引
        outlier_mask = outlier_labels == -1
        outlier_indices[col] = np.flatnonzero(outlier_mask)
    # 创建一个新数组用于存储处理后的数据
    processed_data = []
    removed_values = []
    for i, row in enumerate(cleaned_data):
        new_row = row.copy()
        for col in velocity_columns:
            if i in outlier_indices[col]:
                # 如果速度值被标记为异常，则将其设置为 NaN 并记录
                new_row[col] = np.nan
                count=count+1
        processed_data.append(new_row)
    # 将列表转换为 NumPy 数组
    processed_data = np.array(processed_data)
    return processed_data

def correct_DBS(data,eps=0.9,min=5):
    """校正数据并移除异常值"""
    # 假设速度列是第 3、6、9、12 和 15 列（从0开始计数）
    #eps = np.finfo(np.float64).eps
    velocity_columns = [2, 5, 8, 11, 14]
    outlier_indices = {}
    # 移除包含 NaN 值的行
    nan_count = np.sum(np.isnan(data), axis=1)
    cleaned_data = data[nan_count < 4]
    for col in velocity_columns:
        # 选择当前列
        X = cleaned_data[:, col].reshape(-1, 1)
        nan_mask = np.isnan(X).any(axis=1)
        X = X[~nan_mask]
        if X.size == 0:
            outlier_indices[col] = np.array([], dtype=int)
            continue
        # 使用 DBSCAN 检测异常值
        dbscan = DBSCAN(eps=eps, min_samples=min)  # 需要调整 eps 和 min_samples
        outlier_labels = dbscan.fit_predict(X)

        # 找出异常值的索引
        # 对于 DBSCAN，-1 表示噪声点（即异常值）
        outlier_mask = outlier_labels == -1
        outlier_indices[col] = np.flatnonzero(outlier_mask)

    # 创建一个新数组用于存储处理后的数据
    processed_data = []
    removed_values = []

    for i, row in enumerate(cleaned_data):
        new_row = row.copy()
        for col in velocity_columns:
            if i in outlier_indices[col]:
                # 如果速度值被标记为异常，则将其设置为 NaN 并记录
                new_row[col] = np.nan
                removed_values.append((row[0], row[col]))
        processed_data.append(new_row)

    # 将列表转换为 NumPy 数组
    processed_data = np.array(processed_data)

    return processed_data

def correct_iqr(data):
    """校正数据并移除异常值"""
    # 假设速度列是第 3、6、9、12 和 15 列（从0开始计数）
    velocity_columns = [2, 5, 8, 11, 14]
    outlier_indices = {}

    nan_count = np.sum(np.isnan(data), axis=1)
    cleaned_data = data[nan_count < 4]

    for col in velocity_columns:
        # 选择当前列
        X = cleaned_data[:, col]
        X = X[~np.isnan(X)]

        # 计算第一和第三四分位数
        Q1 = np.percentile(X, 25)
        Q3 = np.percentile(X, 75)

        # 计算 IQR
        IQR = Q3 - Q1

        # 定义异常值的界限
        lower_bound = Q1 - 1.5 * IQR
        upper_bound = Q3 + 1.5 * IQR

        # 找出异常值的索引
        outlier_mask = (X < lower_bound) | (X > upper_bound)
        outlier_indices[col] = np.flatnonzero(outlier_mask)

    # 创建一个新数组用于存储处理后的数据
    processed_data = []
    removed_values = []

    for i, row in enumerate(cleaned_data):
        new_row = row.copy()
        for col in velocity_columns:
            if i in outlier_indices[col]:
                # 如果速度值被标记为异常，则将其设置为 NaN 并记录
                new_row[col] = np.nan
                removed_values.append((row[0], row[col]))
        processed_data.append(new_row)

    # 将列表转换为 NumPy 数组
    processed_data = np.array(processed_data)

    return processed_data

def correct_exponential_smoothing(data, alpha=0.3, threshold=5):
    """
    使用指数平滑法检测并处理异常值。

    参数:
    - data: 输入的二维 NumPy 数组。
    - alpha: 指数平滑系数，默认为 0.5。
    - threshold: 标准差倍数阈值，默认为 3。

    返回:
    - processed_data: 处理后的数据。
    - removed_values: 被标记为异常值的数据点列表。
    """
    # 假设速度列是第 3、6、9、12 和 15 列（从0开始计数）
    velocity_columns = [2, 5, 8, 11, 14]
    outlier_indices = {}
    count2=0
    # 移除包含三个及以上 NaN 值的行
    nan_count = np.sum(np.isnan(data), axis=1)
    cleaned_data = data[nan_count < 3]
    # 创建一个新数组用于存储处理后的数据
    processed_data = []
    removed_values = []

    for col in velocity_columns:
        # 选择当前列
        X = cleaned_data[:, col]

        # 初始化平滑序列
        smoothed_data = [X[0]]

        # 进行指数平滑
        for i in range(1, len(X)):
            smoothed_value = alpha * X[i] + (1 - alpha) * smoothed_data[-1]
            smoothed_data.append(smoothed_value)
        # 计算残差
        residuals = X - np.array(smoothed_data)
        # 计算残差的标准差
        std_dev = np.std(residuals)

        # 找出异常值的索引
        outlier_mask = np.abs(residuals) > threshold * std_dev
        outlier_indices[col] = np.flatnonzero(outlier_mask)

    for i, row in enumerate(cleaned_data):
        new_row = row.copy()
        for col in velocity_columns:
            if i in outlier_indices[col]:
                # 如果速度值被标记为异常，则将其设置为 NaN 并记录
                new_row[col] = np.nan

                removed_values.append((row[0], row[col]))
        processed_data.append(new_row)

    # 将列表转换为 NumPy 数组
    processed_data = np.array(processed_data)
    return processed_data, removed_values,count2

def correct_based_on_change_rate(data, threshold=2.4):
    """
    使用基于变化率的方法检测连续性并进行异常值检测。
    参数:
    - data: 输入的二维 NumPy 数组。
    - threshold: 标准差倍数阈值，默认为 3。
    返回:
    - processed_data: 处理后的数据。
    - removed_values: 被标记为异常值的数据点列表。
    """
    # 假设速度列是第 3、6、9、12 和 15 列（从0开始计数）
    velocity_columns = [2, 5, 8, 11, 14]
    outlier_indices = {}

    # 移除包含 NaN 值的行
    cleaned_data = data[~np.isnan(data).any(axis=1)]

    # 创建一个新数组用于存储处理后的数据
    processed_data = []
    removed_values = []

    for col in velocity_columns:
        # 选择当前列
        X = cleaned_data[:, col]

        # 计算变化率
        change_rates = np.diff(X)

        # 计算变化率的标准差
        std_dev = np.std(change_rates)

        # 找出变化率异常的索引
        outlier_mask = np.abs(change_rates) > threshold * std_dev
        outlier_indices[col] = np.flatnonzero(outlier_mask) + 1  # 因为 diff 减少了长度

    for i, row in enumerate(cleaned_data):
        new_row = row.copy()
        for col in velocity_columns:
            if i in outlier_indices[col]:
                # 如果速度值被标记为异常，则将其设置为 NaN 并记录
                new_row[col] = np.nan
                removed_values.append((row[0], row[col]))
        processed_data.append(new_row)

    # 将列表转换为 NumPy 数组
    processed_data = np.array(processed_data)

    return processed_data, removed_values

def correct_based_on_second_derivative(data, threshold=2.3):
    """
    使用基于变化率的变化率的方法检测连续性并进行异常值检测。

    参数:
    - data: 输入的二维 NumPy 数组。
    - threshold: 标准差倍数阈值，默认为 2.3。

    返回:
    - processed_data: 处理后的数据。
    - removed_values: 被标记为异常值的数据点列表。
    """
    # 假设速度列是第 3、6、9、12 和 15 列（从0开始计数）
    velocity_columns = [2, 5, 8, 11, 14]
    outlier_indices = {}
    global count1
    # 移除包含三个及以上 NaN 值的行
    if data.ndim == 1:
        nan_count = np.sum(np.isnan(data))
    else:
        nan_count = np.sum(np.isnan(data), axis=1)
    cleaned_data = data[nan_count < 3]

    # 创建一个新数组用于存储处理后的数据
    processed_data = []
    removed_values = []
    np.set_printoptions(suppress=True,precision=3, floatmode='maxprec_equal')
    if cleaned_data.size != 0:
        for col in velocity_columns:
            # 选择当前列
            X = cleaned_data[:, col]

            # 计算变化率
            first_derivative = np.diff(X)

            # 计算变化率的变化率（二阶导数）
            second_derivative = np.diff(first_derivative)

            # 计算二阶导数的标准差
            std_dev = np.nanstd(second_derivative)

            # 找出二阶导数异常的索引
            outlier_mask = np.abs(second_derivative) > threshold * std_dev
            outlier_indices[col] = np.flatnonzero(outlier_mask) + 1  # 因为两次 diff 减少了长度

        for i, row in enumerate(cleaned_data):
            new_row = row.copy()

            for col in velocity_columns:
                if i in outlier_indices[col]:
                    # 如果速度值被标记为异常，则将其设置为 NaN 并记录
                    new_row[col] = np.nan
                    count1=count1+1
            processed_data.append(new_row)

    # 将列表转换为 NumPy 数组
    processed_data = np.array(processed_data)

    return processed_data

def write_data(data, new_filename, comments):
    """将处理后的数据写入新文件，保持原格式，速度数据保留两位小数"""
    global  aftfactor
    global count
    global count1
    global count0
    global count10
    global prefactor
    with open(new_filename, 'w') as file:
        new_comment = ('#quantitative indicators:    {:d}    {:d}    {:d}    {:d}    {:.4f}    {:.4f}                  \n'.format(
                count10, count0, count, count1, prefactor, aftfactor))
        comments[10]=new_comment
        for i, comment in enumerate(comments):
            file.write(comment)

        # 遍历数据行
        for row in data:
            formatted_row = [
                "    " +str(round(value, 2) if idx in {2, 5, 8, 11, 14} else str(value))  # 速度数据保留两位小数,四个空格
                for idx, value in enumerate(row)
            ]
            file.write(''.join(formatted_row) + '\n')
def completion(data):
    global  aftfactor
    # 从输入数据中提取各列
    heights = data[:, 0]
    r2 = data[:, 1]
    rv1 = data[:, 2]
    r4 = data[:, 3]
    r5 = data[:, 4]
    rv2 = data[:, 5]
    r7 = data[:, 6]
    r8 = data[:, 7]
    rv3 = data[:, 8]
    r10 = data[:, 9]
    r11 = data[:, 10]
    rv4 = data[:, 11]
    r13 = data[:, 12]
    r14 = data[:, 13]
    rv5 = data[:, 14]
    r16 = data[:, 15]

    # Handling missing values in rv5
    pre = -1
    aft = -1
    for i, value in enumerate(rv5):
        if math.isnan(value) and pre >= 0:
            aft = i
        else:
            if pre < aft:
                if pre >= 0:
                    for j in range(pre + 1, aft + 1):
                        rv5[j] = rv5[j - 1] + (rv5[aft + 1] - rv5[pre]) / (aft - pre)
            pre = i

    # Handling missing values in rv1 and rv2
    flag1 = False
    for i, (v1, v2) in enumerate(zip(rv1, rv2)):
        if math.isnan(v1) or math.isnan(v2):
            if math.isnan(v1) and math.isnan(v2):
                flag1 = True
            elif math.isnan(v1):
                rv1[i] = -rv2[i]
            else:
                rv2[i] = -rv1[i]

    # Handling missing values in rv3 and rv4
    flag3 = False
    for i, (v3, v4) in enumerate(zip(rv3, rv4)):
        if math.isnan(v3) or math.isnan(v4):
            if math.isnan(v3) and math.isnan(v4):
                flag3 = True
            elif math.isnan(v3):
                rv3[i] = -rv4[i]
            else:
                rv4[i] = -rv3[i]

    # Handling missing values in rv1 and rv2 if flag1 is set
    if flag1:
        pre = -1
        aft = -1
        for i, value in enumerate(rv1):
            if math.isnan(value) and pre >= 0:
                aft = i
            else:
                if pre < aft:
                    if pre >= 0:
                        for j in range(pre + 1, aft + 1):
                            rv1[j] = rv1[j - 1] + (rv1[aft + 1] - rv1[pre]) / (2 * (aft - pre)) + (rv2[pre] - rv2[aft + 1]) / (2 * (aft - pre))
                            rv2[j] = rv2[j - 1] + (rv2[aft + 1] - rv2[pre]) / (2 * (aft - pre)) + (rv1[pre] - rv1[aft + 1]) / (2 * (aft - pre))
                pre = i

    # Handling missing values in rv3 and rv4 if flag3 is set
    if flag3:
        pre = -1
        aft = -1
        for i, value in enumerate(rv3):
            if math.isnan(value) and pre >= 0:
                aft = i
            else:
                if pre < aft:
                    if pre >= 0:
                        for j in range(pre + 1, aft + 1):
                            rv3[j] = rv3[j - 1] + (rv3[aft + 1] - rv3[pre]) / (2 * (aft - pre)) + (rv4[pre] - rv4[aft + 1]) / (2 * (aft - pre))
                            rv4[j] = rv4[j - 1] + (rv4[aft + 1] - rv4[pre]) / (2 * (aft - pre)) + (rv3[pre] - rv3[aft + 1]) / (2 * (aft - pre))
                pre = i

    sum = 0
    len1 = 0
    len2 = 0

    for i, (v1, v2) in enumerate(zip(rv1, rv2)):
        if not math.isnan(v1):
            sum += abs(abs(rv1[i]) - abs(rv2[i])) ** 2
            len1 += 1
    for j, (v1, v2) in enumerate(zip(rv1, rv2)):
        if not math.isnan(v1):
            sum += abs(abs(rv1[j]) - abs(rv2[j])) ** 2
            len2 += 1

    if (len1+len2)!=0:
        aftfactor = sum / (len1 + len2)
    else:
        aftfactor=999


    # 更新数据
    updated_data = np.column_stack((heights, r2, rv1, r4, r5, rv2, r7, r8, rv3, r10, r11, rv4, r13, r14, rv5, r16))

    return updated_data, aftfactor

def draw(data):

    # 提取所需列
    heights = data[:, 0]
    rv1 = data[:, 2]
    rv2 = data[:, 5]
    rv3 = data[:, 8]
    rv4 = data[:, 11]
    rv5 = data[:, 14]

    # 找到 heights 小于27000的索引
    idx_low = heights < 27000
    # 找到 heights 大于等于27000的索引
    idx_high = heights >= 27000

    # 分割 rv1 到不同的部分
    rv1_low = rv1[idx_low]
    heights_low = heights[idx_low]
    rv1_high = rv1[idx_high]
    heights_high = heights[idx_high]

    # 分割其他 rv 到不同的部分
    rv2_low = rv2[idx_low]
    rv2_high = rv2[idx_high]
    rv3_low = rv3[idx_low]
    rv3_high = rv3[idx_high]
    rv4_low = rv4[idx_low]
    rv4_high = rv4[idx_high]
    rv5_low = rv5[idx_low]
    rv5_high = rv5[idx_high]

    # 绘制 Beams 的低高度部分
    plt.figure(figsize=(10, 15))
    plt.plot(rv1_low, heights_low, 'bo-', label='Beam 1 (low)', markersize=4)
    plt.plot(rv2_low, heights_low, 'ro-', label='Beam 2 (low)', markersize=4)
    plt.plot(rv3_low, heights_low, 'go-', label='Beam 3 (low)', markersize=4)
    plt.plot(rv4_low, heights_low, 'mo-', label='Beam 4 (low)', markersize=4)
    plt.plot(rv5_low, heights_low, 'co-', label='Beam 5 (low)', markersize=4)

    # 绘制 Beams 的高高度部分
    plt.plot(rv1_high, heights_high, 'b--', label='Beam 1 (high)', markersize=4)
    plt.plot(rv2_high, heights_high, 'r--', label='Beam 2 (high)', markersize=4)
    plt.plot(rv3_high, heights_high, 'g--', label='Beam 3 (high)', markersize=4)
    plt.plot(rv4_high, heights_high, 'm--', label='Beam 4 (high)', markersize=4)
    plt.plot(rv5_high, heights_high, 'c--', label='Beam 5 (high)', markersize=4)

    # 添加图例
    plt.legend()

    # 设置坐标轴范围
    plt.xlim([-10, 10])
    plt.ylim([0, 30000])

    # 设置图表属性
    plt.xlabel('Radial Velocity (m/s)')
    plt.ylabel('Height (m)')

    # 假设 time 和 freq 是从注释中提取的，这里用示例值代替
    # 解析时间与频率信息
    time = comments[17:32].strip()
    freq = comments[19:26].strip()
    plt.title(f"{time} {freq}")

    plt.show()

    return f"{time} {freq}"

if __name__ == "__main__":
    # 量化指标相关的初始化
    count10 = 0; count0 = 0; count = 0; count1 = 0
    prefactor = 0; aftfactor = 0

    # 文件路径读入
    filepath = r"/Users/zyqyq/Program/数据集/L1B/202408"
    new_folder_path = r"/Users/zyqyq/Program/数据集/L1BP/202408"

    # 记录程序开始时间
    start_time = datetime.now()

    for filename1 in os.listdir(filepath): 
        # 跳过 .DS_Store 文件
        if filename1 == '.DS_Store':
            continue
        new_folder_full_path = os.path.join(new_folder_path, filename1)
        # 检查目录是否存在，如果不存在则创建
        if not os.path.exists(new_folder_full_path):
            os.mkdir(new_folder_full_path)
        for filename2 in os.listdir(os.path.join(filepath, filename1)):
            # 跳过 .DS_Store 文件
            if filename2 == '.DS_Store':
                continue
            file_path = os.path.join(os.path.join(filepath, filename1), filename2)
                
            # 读取数据
            original_data, comments = read_data(file_path)
            count10 = len(original_data[:, 2])
            factordetect(original_data)

            # 校正和处理数据
            # original_data = correct_DBS(high_height_data, 1.7, 8)
            # 分割数据
            heights = original_data[:, 0]
            low_height_mask = heights < 30000
            high_height_mask = (heights > 60000) & (heights < 90000)

            low_height_data = original_data[low_height_mask]
            high_height_data = original_data[high_height_mask]

            # 校正和处理数据
            processed_low_height_data = correct_low(low_height_data)
            processed_high_height_data = correct_high(high_height_data)

            # 合并处理后的数据
            if processed_high_height_data.size > 0:
                processed_data = np.concatenate((processed_low_height_data, processed_high_height_data), axis=0)
            else:
                processed_data = processed_low_height_data.copy()
            count0 = len(processed_data)
            print(count0+" ",end="")
            # 保持数据的原始顺序
            # processed_data = processed_data[np.argsort(heights)]

            if processed_data.size == 0:
                updated_data, aftfactor = [], -1
            else:
                updated_data, aftfactor = completion(processed_data)

            # 生成新文件名
            new_file_name = os.path.splitext(filename2)[0] + '_processed' + os.path.splitext(filename2)[1]
            # 构建新文件路径
            new_file_path = os.path.join(new_folder_full_path, new_file_name)
            # 将处理后的数据写入新文件
            write_data(updated_data, new_file_path, comments)

    print(f"Data processing completed.\n New file saved as '{new_folder_path}'")
    # 记录程序结束时间
    end_time = datetime.now()

    # 计算并打印程序运行时间
    run_time = (end_time - start_time).total_seconds()
    print(f"所有文件处理完成，程序运行时间：{run_time}秒")