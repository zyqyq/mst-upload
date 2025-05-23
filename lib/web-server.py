import argparse
import asyncio
import websockets
import json
import libfix_for_flutter
import change_for_flutter

# 全局变量，用于存储定时器任务
timer_task = None

# WebSocket 服务端处理逻辑
async def handle_connection(websocket):
    global timer_task
    async for message in websocket:
        try:
            # 解析客户端发送的 JSON 数据
            data = json.loads(message)
            task_type = data.get("task_type")
            task_id = data.get("task_id")  # 获取任务ID
            source_file = data.get("source_file")
            output_file = data.get("output_file")

            # 验证必要参数
            if not all([task_type, source_file, output_file]):
                response = {
                    "error": "Missing required parameters",
                    "task_id": task_id  # 包含任务ID在错误响应中
                }
                print(f"→ 发送消息: {response}")
                await websocket.send(json.dumps(response))
                continue

            # 根据任务类型调用不同的处理函数
            if task_type == "optimize":
                libfix_for_flutter.optimize_data(source_file, output_file)
                result = "optimize done"
            elif task_type == "convert":
                change_for_flutter.convert_data(source_file, output_file)
                result = "convert done"
            else:
                response = {
                    "error": f"Unknown task type: {task_type}",
                    "task_id": task_id
                }
                await websocket.send(json.dumps(response))
                continue

            # 构建成功响应，包含任务ID
            response = {
                "result": result,
                "task_type": task_type,
                "task_id": task_id,
                "status": "completed"
            }
            await websocket.send(json.dumps(response))
            print(f"→ 发送消息: {response}")

            # 重置定时器
            if timer_task is not None:
                timer_task.cancel()
            timer_task = asyncio.create_task(stop_server_after_timeout())

        except json.JSONDecodeError:
            response = {
                "error": "Invalid JSON format",
                "task_id": data.get("task_id", "unknown") if isinstance(data, dict) else "unknown"
            }
            print(f"⚠️ JSON 解析错误: {e}")
            await websocket.send(json.dumps(response))
        except Exception as e:
            # 捕获异常并返回错误信息
            response = {
                "error": str(e),
                "task_id": data.get("task_id", "unknown") if isinstance(data, dict) else "unknown"
            }
            print(f"⚠️ 处理请求时发生错误: {e}")
            await websocket.send(json.dumps(response))

# 定时器任务：3分钟后停止服务器
async def stop_server_after_timeout():
    await asyncio.sleep(180)  # 3分钟
    print("3分钟内无连接，自动结束程序...")
    asyncio.get_event_loop().stop()

# 启动 WebSocket 服务器
async def start_server(port):
    async with websockets.serve(handle_connection, "localhost", port):  # 修改：使用传入的端口号
        print(f"WebSocket server started on ws://localhost:{port}")  # 修改：动态打印端口号
        await asyncio.Future()  # 持续运行

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run WebSocket server with a specified port.")
    parser.add_argument("--port", type=int, default=8765, help="Port number for the WebSocket server")  # 新增：添加 --port 参数
    args = parser.parse_args()

    # 启动 WebSocket 服务器，传入端口号
    asyncio.run(start_server(args.port))