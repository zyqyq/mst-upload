import asyncio
import websockets

async def handle_connection(websocket):
    print(f"客户端连接成功! Path:")
    await websocket.send("Hello!")

async def main():
    async with websockets.serve(handle_connection, "localhost", 8765):
        await asyncio.Future()  # 永久运行

asyncio.run(main())