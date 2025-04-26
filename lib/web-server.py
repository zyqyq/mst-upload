import asyncio
import websockets
import json
import libfix_for_flutter
import change_for_flutter

# WebSocket 服务端处理逻辑
async def handle_connection(websocket):
    async for message in websocket:
        try:
            # 解析客户端发送的 JSON 数据
            print("Received message:", message)
            data = json.loads(message)
            task_type = data.get("task_type")
            source_file = data.get("source_file")
            output_file = data.get("output_file")

            if not source_file or not output_file:
                await websocket.send(json.dumps({"error": "Missing source_file or output_file"}))
                continue

            # 根据任务类型调用不同的处理函数
            if task_type == "optimize":
                result = libfix_for_flutter.optimize_data(source_file, output_file)
            elif task_type == "convert":
                result = change_for_flutter.convert_data(source_file, output_file)
            else:
                await websocket.send(json.dumps({"error": "Unknown task type"}))
                continue

            # 返回处理结果
            await websocket.send(json.dumps({"result": result}))
        except Exception as e:
            # 捕获异常并返回错误信息
            await websocket.send(json.dumps({"error": str(e)}))

# 启动 WebSocket 服务器
async def start_server():
    async with websockets.serve(handle_connection, "localhost", 8765):
        print("WebSocket server started on ws://localhost:8765")
        await asyncio.Future()  # 持续运行

if __name__ == "__main__":
    # 启动 WebSocket 服务器
    asyncio.run(start_server())