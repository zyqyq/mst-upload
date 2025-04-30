def normalize_filename(filename):
    # 如果有后缀名，分割主名和后缀
    parts = filename.rsplit('.', 1)
    main_name = parts[0]
    suffix = parts[1] if len(parts) > 1 else ''

    # 处理文件名中的版本信息（假设_processed是版本差异）
    normalized_main_name = main_name.replace('_processed', '')

    # 返回标准化后的文件名（去除版本差异）
    return normalized_main_name

def read_filenames(file_path):
    with open(file_path, 'r') as file:
        filenames = [line.strip() for line in file.readlines()]
    return filenames

def find_unique_files(file_a_path, file_b_path):
    # 读取两个文件中的文件名列表
    files_a = read_filenames(file_a_path)
    files_b = read_filenames(file_b_path)

    # 标准化文件名
    normalized_files_a = {normalize_filename(f): f for f in files_a}
    normalized_files_b = {normalize_filename(f): f for f in files_b}

    # 找出存在于A而不存在于B的文件名
    unique_files = []
    for norm_name, original_name in normalized_files_a.items():
        if norm_name not in normalized_files_b:
            unique_files.append(original_name)

    return unique_files

if __name__ == "__main__":
    file_a = "/Users/zyqyq/Desktop/raw.txt"  # 替换为你的A文件路径
    file_b = "/Users/zyqyq/Desktop/tmp.txt"  # 替换为你的B文件路径

    unique_files = find_unique_files(file_a, file_b)
    print("存在于A而不存在于B的文件名：")
    for file in unique_files:
        print(file)