"""给副屏固件发模拟数据，用于不开 Sysmon 时验证屏幕。

每 2 秒依次发 S、P，当前是用量屏时再发 U（固定的假数据）。
板子回 TAP 时打印出来并切到下一屏，像 Mac 端一样立即补发 P（和 U）。

用法（PlatformIO 的 venv 自带 pyserial）：
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page cl
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
"""
import argparse
import math
import time

import serial

PAGES = ["sys", "cl", "gpt"]
FAKE_USAGE = {
    "cl": "U svc=cl st=ok age=60 plan=max h5=42 h5r=7980 wk=67 wkd=4 wkt=1400 op=12 so=28",
    "gpt": "U svc=gpt st=exp age=3600 plan=plus h5=6 wk=35 wkd=2 wkt=900",
}
CYCLE_SECS = 6


def open_port(path):
    # 先把 DTR/RTS 设为 False 再 open，避免触发板子的自动复位电路
    port = serial.Serial()
    port.port = path
    port.baudrate = 115200
    port.dtr = False
    port.rts = False
    port.timeout = 0
    port.open()
    return port


def send(port, line):
    port.write((line + "\n").encode())
    print(line, flush=True)


def send_page(port, page):
    send(port, f"P {page} i={PAGES.index(page) + 1} n={len(PAGES)}")
    if page in FAKE_USAGE:
        send(port, FAKE_USAGE[page])


def next_page(page):
    return PAGES[(PAGES.index(page) + 1) % len(PAGES)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    parser.add_argument("--off", action="store_true", help="只发一行 OFF 后退出")
    parser.add_argument("--page", choices=PAGES, default="sys", help="起始页")
    parser.add_argument("--cycle", action="store_true", help=f"每 {CYCLE_SECS} 秒自动切到下一屏")
    args = parser.parse_args()

    port = open_port(args.port)
    if args.off:
        port.write(b"OFF\n")
        port.flush()
        return

    page = args.page
    levels = [1, 2, 4]
    start = time.monotonic()
    next_sample = start
    next_cycle = start + CYCLE_SECS
    tick = 0
    received = b""
    while True:
        now = time.monotonic()
        if now >= next_sample:
            t = now - start
            cpu = tick * 5 % 101
            lvl = levels[int(t // 20) % 3]
            rx = int(15 * 1024 * 1024 * (0.5 + 0.5 * math.sin(t / 15)))
            tx = int(1024 * 1024 * (0.5 + 0.5 * math.sin(t / 7)))
            send(port, f"S cpu={cpu} mem=51 lvl={lvl} rx={rx} tx={tx}")
            send_page(port, page)
            tick += 1
            next_sample += 2

        if args.cycle and now >= next_cycle:
            page = next_page(page)
            send_page(port, page)
            next_cycle += CYCLE_SECS

        received += port.read(256)
        while b"\n" in received:
            raw, received = received.split(b"\n", 1)
            line = raw.decode(errors="replace").strip()
            if not line:
                continue
            print(f"< {line}", flush=True)
            if line == "TAP":
                page = next_page(page)
                send_page(port, page)

        time.sleep(0.02)


if __name__ == "__main__":
    main()
