import os

def get_pids_by_port(port):
    """
    获取占用指定端口的进程ID (PID)
    """
    try:
        # 使用 lsof 命令查找占用端口的进程
        result = os.popen(f"lsof -i :{port}").read()
        lines = result.strip().split('\n')
        if len(lines) <= 1:
            return []  # 没有找到占用端口的进程
        pids = []
        for line in lines[1:]:  # 跳过表头
            parts = line.split()
            pid = parts[1]  # PID在lsof输出的第二列
            pids.append(pid)
        return list(set(pids))  # 去重
    except Exception as e:
        print(f"获取端口 {port} 的进程失败: {e}")
        return []

def kill_process(pid):
    """
    强制终止指定PID的进程
    """
    try:
        os.system(f"kill -9 {pid}")
        print(f"已强制终止进程 PID={pid}")
    except Exception as e:
        print(f"终止进程 PID={pid} 失败: {e}")

def close_ports(start_port, end_port):
    """
    关闭指定区间内的所有端口占用进程
    """
    for port in range(start_port, end_port + 1):
        pids = get_pids_by_port(port)
        if not pids:
            print(f"端口 {port} 未被占用")
            continue
        print(f"端口 {port} 被以下进程占用: {pids}")
        for pid in pids:
            kill_process(pid)

if __name__ == "__main__":
    start_port = int(input("请输入起始端口号: "))
    end_port = int(input("请输入结束端口号: "))
    close_ports(start_port, end_port)