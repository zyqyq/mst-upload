import numpy as np
from sklearn.neighbors import LocalOutlierFactor
from sklearn.cluster import DBSCAN
import math
import sys
import pandas as pd
import re
import os
from datetime import datetime
import argparse
from joblib import Parallel, delayed

count10=0#原始数据RecordNumber
count0=0#去除3NaN后的数RecordNumProcessed
count=0#记录LOF去除的点Lof_delete_dot
count1=0#记录SECOND去除的点Seconded_delete_dot
prefactor=0#处理前有关对称度的参数，NaN不参与
aftfactor=0#处理后与对称度有关的参数，NaN不参与

def read_data(filename):
    """
    使用Pandas高效读取但保持NumPy数组输出的函数
    返回格式: (data_numpy, comments) 与原程序完全一致
    """
    with open(filename, 'r') as file:
        # 1. 保持完全相同的注释行读取方式
        comments = [next(file) for _ in range(33)]
        
        # 3. 使用Pandas读取数据(高性能)
        df = pd.read_csv(
            file,
            sep=r'\s+',
            header=None,          # 不将第一行作为列名
            na_values=['-9999999', '-999999', '-99999'],
            dtype=np.float64
        )
    
    # 4. 转换为与原始程序完全相同的NumPy数组格式
    data_numpy = df.to_numpy()
    
    # 5. 确保空数据时返回正确形状的数组(与原程序一致)
    if data_numpy.size == 0:
        return np.empty((0, len(df.columns)), dtype=np.float64), comments
    
    return data_numpy, comments

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
    if processed_data.size == 0:
        processed_data = np.empty((0, data.shape[1]))
    return processed_data

def correct_DBS(data, eps=0.9, min=5, n_jobs=-1):
    """校正数据并移除异常值（向量化和并行化优化版本）"""
    global count
    # 速度列索引（从0开始计数）
    velocity_columns = [2, 5, 8, 11, 14]
    
    # 1. 向量化移除包含过多NaN值的行
    nan_count = np.sum(np.isnan(data), axis=1)
    cleaned_data = data[nan_count < 4]
    
    if cleaned_data.size == 0:
        return np.empty((0, data.shape[1]))
    
    # 2. 并行处理每个速度列
    def process_column(col_data, col_idx, eps, min):
        # 移除NaN值
        non_nan_mask = ~np.isnan(col_data)
        X = col_data[non_nan_mask].reshape(-1, 1)
        
        if X.size == 0:
            return np.array([], dtype=int)
        
        # DBSCAN检测异常值
        dbscan = DBSCAN(eps=eps, min_samples=min)
        outlier_labels = dbscan.fit_predict(X)
        
        # 获取异常值在原数据中的索引
        outlier_mask = outlier_labels == -1
        original_indices = np.where(non_nan_mask)[0][outlier_mask]
        
        return original_indices
    
    # 提取各列数据
    columns_data = [cleaned_data[:, col] for col in velocity_columns]
    
    # 并行执行DBSCAN检测
    outlier_indices_list = Parallel(n_jobs=n_jobs)(
        delayed(process_column)(col_data, col_idx, eps, min)
        for col_idx, col_data in enumerate(columns_data)
    )
    
    # 3. 向量化处理异常值标记
    processed_data = cleaned_data.copy()
    outlier_mask = np.zeros_like(processed_data, dtype=bool)
    
    for col_idx, col in enumerate(velocity_columns):
        outlier_indices = outlier_indices_list[col_idx]
        outlier_mask[outlier_indices, col] = True
    
    # 标记异常值为NaN
    processed_data[outlier_mask] = np.nan
    
    # 计算被移除的值的数量
    count = np.sum(outlier_mask)
    
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
    if processed_data.size == 0:
        processed_data = np.empty((0, data.shape[1]))

    return processed_data, removed_values

def correct_based_on_second_derivative(data, threshold=2.3):
    """
    纯NumPy向量化优化的二阶导数异常检测
    
    参数:
    - data: 输入的二维NumPy数组
    - threshold: 标准差倍数阈值
    
    返回:
    - processed_data: 处理后的数据
    - removed_count: 被移除的异常值数量
    """
    velocity_columns = [2, 5, 8, 11, 14]
    global count1
    
    # 向量化NaN处理
    nan_mask = np.sum(np.isnan(data), axis=1) < 3 if data.ndim > 1 else np.array([True]*len(data))
    cleaned_data = data[nan_mask]
    
    if cleaned_data.size == 0:
        return np.empty((0, data.shape[1])) if data.ndim > 1 else np.array([]), 0
    
    # 预分配结果数组
    processed_data = cleaned_data.copy()
    removed_count = 0
    
    # 同时对所有速度列进行操作
    for col in velocity_columns:
        col_data = cleaned_data[:, col]
        
        # 计算二阶导数 (向量化)
        first_deriv = np.diff(col_data, prepend=np.nan)  # 保持长度一致
        second_deriv = np.diff(first_deriv, prepend=np.nan)
        
        # 计算阈值
        std_dev = np.nanstd(second_deriv)
        if np.isnan(std_dev) or std_dev == 0:
            continue
        
        # 向量化异常检测
        outlier_mask = np.abs(second_deriv) > threshold * std_dev
        outlier_mask[:2] = False  # 前两个点因差分不完整而排除
        
        # 向量化替换
        processed_data[outlier_mask, col] = np.nan
        count1 += np.sum(outlier_mask)
    
    return processed_data


def write_data(data, new_filename, comments):
    """将处理后的数据写入新文件，保持原格式，速度数据保留两位小数"""
    global aftfactor
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
        formatted_rows = [
            "    ".join([f"{val:.2f}" if idx in {2,5,8,11,14} else str(val) 
                        for idx, val in enumerate(row)]) 
            for row in data
        ]
        file.write("\n".join(formatted_rows))

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


def optimize_data(source_file, output_file):
    """
    处理数据的核心逻辑，封装为主函数可调用的函数。
    
    参数:
    - source_file: 输入文件路径
    - output_file: 输出文件路径
    
    返回:
    - count10, count0, count, count1, prefactor, aftfactor: 量化指标
    """
    # 量化指标相关的初始化
    global count10, count0, count, count1, prefactor, aftfactor
    count10 = 0; count0 = 0; count = 0; count1 = 0
    prefactor = 0; aftfactor = 0

    # 读取数据
    original_data, comments = read_data(source_file)
    count10 = len(original_data[:, 2])
    factordetect(original_data)

    # 校正和处理数据
    heights = original_data[:, 0]
    low_height_mask = heights < 30000
    high_height_mask = (heights > 60000) & (heights < 90000)

    low_height_data = original_data[low_height_mask]
    high_height_data = original_data[high_height_mask]

    # 校正和处理数据
    processed_low_height_data = correct_low(low_height_data)
    processed_high_height_data = correct_high(high_height_data)
    
    # 在合并前确保两者均为2D
    if processed_low_height_data.ndim == 1:
        processed_low_height_data = processed_low_height_data.reshape(-1, 1)
    if processed_high_height_data.ndim == 1:
        processed_high_height_data = processed_high_height_data.reshape(-1, 1)

    # 合并处理后的数据
    if processed_high_height_data.size > 0:
        processed_data = np.concatenate((processed_low_height_data, processed_high_height_data), axis=0)
    else:
        processed_data = processed_low_height_data.copy()
    count0 = len(processed_data)

    if processed_data.size == 0:
        updated_data, aftfactor = [], -1
    else:
        updated_data, aftfactor = completion(processed_data)

    # 将处理后的数据写入新文件
    write_data(updated_data, output_file, comments)
    
    return count10, count0, count, count1, prefactor, aftfactor


if __name__ == "__main__":
    # 创建 ArgumentParser 对象
    parser = argparse.ArgumentParser(description="Process L1B data files.")
    parser.add_argument("source_file", type=str, help="Path to the source file")
    parser.add_argument("output_file", type=str, help="Path to the output file")

    # 解析命令行参数
    args = parser.parse_args()

    # 调用 process_data 函数处理数据
    optimize_data(args.source_file, args.output_file)