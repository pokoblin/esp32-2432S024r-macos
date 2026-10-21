"""给副屏固件发模拟数据，用于在 Mac 端程序完成前验证屏幕。

用法（PlatformIO 的 venv 自带 pyserial）：
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
"""
import argparse
import math
import time

import serial


def open_port(path):
    # 先把 DTR/RTS 设为 False 再 open，避免触发板子的自动复位电路
    port = serial.Serial()
    port.port = path
    port.baudrate = 115200
    port.dtr = False
    port.rts = False
    port.open()
    return port


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    parser.add_argument("--off", action="store_true", help="只发一行 OFF 后退出")
    args = parser.parse_args()

    port = open_port(args.port)
    if args.off:
        port.write(b"OFF\n")
        port.flush()
        return

    levels = [1, 2, 4]
    start = time.monotonic()
    tick = 0
    while True:
        t = time.monotonic() - start
        cpu = tick * 5 % 101
        lvl = levels[int(t // 20) % 3]
        rx = int(15 * 1024 * 1024 * (0.5 + 0.5 * math.sin(t / 15)))
        tx = int(1024 * 1024 * (0.5 + 0.5 * math.sin(t / 7)))
        line = f"S cpu={cpu} mem=51 lvl={lvl} rx={rx} tx={tx}\n"
        port.write(line.encode())
        print(line, end="", flush=True)
        tick += 1
        time.sleep(2)


if __name__ == "__main__":
    main()
