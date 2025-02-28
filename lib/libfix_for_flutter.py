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

count10=0#原始数据RecordNumber
count0=0#去除3NaN后的数RecordNumProcessed
count=0#记录LOF去除的点Lof_delete_dot
count1=0#记录SECOND去除的点Seconded_delete_dot
prefactor=0#处理前有关对称度的参数，NaN不参与
aftfactor=0#处理后与对称度有关的参数，NaN不参与
def read_data(filename):
    """读取原始数据文件,并收集前33行的注释"""
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

    # 使用向量化计算对称度参数
    v1 = cleaned_data[:, 2]
    v2 = cleaned_data[:, 5]
    v3 = cleaned_data[:, 8]
    v4 = cleaned_data[:, 11]

    # 计算对称度参数
    valid_mask = ~np.isnan(v1) & ~np.isnan(v2)
    sum1 = np.sum(np.abs(np.abs(v1[valid_mask]) - np.abs(v2[valid_mask])) ** 2)
    len1 = np.sum(valid_mask)

    valid_mask = ~np.isnan(v3) & ~np.isnan(v4)
    sum2 = np.sum(np.abs(np.abs(v3[valid_mask]) - np.abs(v4[valid_mask])) ** 2)
    len2 = np.sum(valid_mask)

    global prefactor
    prefactor = (sum1 + sum2) / (len1 + len2) if (len1 + len2) > 0 else -1

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
    global count
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
                count=count+1
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

    # 使用向量化方法处理缺失值
    rv5 = np.where(np.isnan(rv5), np.roll(rv5, 1), rv5)

    # 使用向量化方法处理 rv1 和 rv2 的缺失值
    rv1 = np.where(np.isnan(rv1), -rv2, rv1)
    rv2 = np.where(np.isnan(rv2), -rv1, rv2)

    # 使用向量化方法处理 rv3 和 rv4 的缺失值
    rv3 = np.where(np.isnan(rv3), -rv4, rv3)
    rv4 = np.where(np.isnan(rv4), -rv3, rv4)

    # 计算对称度参数
    valid_mask = ~np.isnan(rv1) & ~np.isnan(rv2)
    sum1 = np.sum(np.abs(np.abs(rv1[valid_mask]) - np.abs(rv2[valid_mask])) ** 2)
    len1 = np.sum(valid_mask)

    valid_mask = ~np.isnan(rv3) & ~np.isnan(rv4)
    sum2 = np.sum(np.abs(np.abs(rv3[valid_mask]) - np.abs(rv4[valid_mask])) ** 2)
    len2 = np.sum(valid_mask)

    if (len1 + len2) != 0:
        aftfactor = (sum1 + sum2) / (len1 + len2)
    else:
        aftfactor = 999

    # 更新数据
    updated_data = np.column_stack((heights, r2, rv1, r4, r5, rv2, r7, r8, rv3, r10, r11, rv4, r13, r14, rv5, r16))

    return updated_data, aftfactor

if __name__ == "__main__":
    # 创建 ArgumentParser 对象
    parser = argparse.ArgumentParser(description="Process L1B data files.")
    parser.add_argument("source_file", type=str, help="Path to the source file")
    parser.add_argument("output_file", type=str, help="Path to the output file")

    # 解析命令行参数
    args = parser.parse_args()

    # 量化指标相关的初始化
    count10 = 0; count0 = 0; count = 0; count1 = 0
    prefactor = 0; aftfactor = 0



    # 读取数据
    original_data, comments = read_data(args.source_file)
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

    # 合并处理后的数据
    if processed_high_height_data.size > 0:
        processed_data = np.concatenate((processed_low_height_data, processed_high_height_data), axis=0)
    else:
        processed_data = processed_low_height_data.copy()
    count0 = len(processed_data);
    #print(count0, end="")

    if processed_data.size == 0:
        updated_data, aftfactor = [], -1
    else:
        updated_data, aftfactor = completion(processed_data)

    # 将处理后的数据写入新文件
    write_data(updated_data, args.output_file, comments)
