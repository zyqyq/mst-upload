import asyncio
import websockets
import json

async def test_websocket():
    # 替换为您的服务器地址
    uri = "ws://localhost:8765/api"
    
    while True:  # 循环尝试连接服务器
        try:
            async with websockets.connect(uri) as websocket:
                print("→ 已成功连接到服务器")
                
                # 测试消息（根据您的服务器协议调整）
                test_msg = {
                    "task_type": "optimize",  # 或 "convert"
                    "source_file": "input.txt",
                    "output_file": "output.txt"
                }
                
                print(f"→ 发送消息: {test_msg}")
                await websocket.send(json.dumps(test_msg))
                
                response = await websocket.recv()
                print(f"← 收到响应: {response}")
                break  # 连接成功后退出循环
            
        except Exception as e:
            print(f"⚠️ 连接失败，正在重试... 错误信息: {e}")
            await asyncio.sleep(5)  # 等待1秒后重试

if __name__ == "__main__":
    asyncio.run(test_websocket())