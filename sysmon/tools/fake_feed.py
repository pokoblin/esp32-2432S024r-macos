"""给副屏固件发模拟数据，用于不开 Sysmon 时验证屏幕。

每 2 秒依次发 S、P、T、B，当前是用量屏时再发 U（固定的假数据）。
T 是一个按真实秒数倒数的假番茄，--phase 选阶段；B 默认没有横幅，--banner 选一种横幅。
板子回 TAP 时打印出来：有横幅就关掉横幅，否则切到下一屏，像 Mac 端一样立即补发。

用法（PlatformIO 的 venv 自带 pyserial）：
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page cl
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page pomo --phase paused
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --banner done
    ~/.platformio-venv/bin/python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
"""
import argparse
import math
import time

import serial

PAGES = ["sys", "pomo", "cl", "gpt"]
# 阶段 → (st, 是否在走, 总秒数)
PHASES = {
    "idle": ("idle", False, 1500),
    "focus": ("focus", True, 1500),
    "short": ("short", True, 300),
    "long": ("long", True, 900),
    "paused": ("focus", False, 1500),
}
BANNERS = {
    "done": "B k=done xw=1 xs=1 led=1",
    "brk": "B k=brk led=1",
    "sit": "B k=sit min=52 led=1",
    "water": "B k=water min=60 led=1",
}
FAKE_USAGE = {
    "cl": "U svc=cl st=ok age=60 plan=max h5=42 h5r=7980 wk=67 wkd=4 wkt=1400 md=Fable mw=12",
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


def timer_line(phase, started):
    """假番茄：从一半开始，走着时按真实秒数倒数；结束时刻按本机时间算。"""
    st, running, total = PHASES[phase]
    rem = total if st == "idle" else total // 2
    if running:
        rem = max(0, rem - int(time.monotonic() - started))
    line = f"T st={st} run={1 if running else 0} rem={rem} tot={total}"
    if running:
        end = time.localtime(time.time() + rem)
        line += f" end={end.tm_hour * 100 + end.tm_min}"
    rd = 2 if st in ("focus", "idle") else 1
    return line + f" rd={rd} rn=4 dn=5 dm=125 key=1"


def next_page(page):
    return PAGES[(PAGES.index(page) + 1) % len(PAGES)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    parser.add_argument("--off", action="store_true", help="只发一行 OFF 后退出")
    parser.add_argument("--page", choices=PAGES, default="sys", help="起始页")
    parser.add_argument("--cycle", action="store_true", help=f"每 {CYCLE_SECS} 秒自动切到下一屏")
    parser.add_argument("--phase", choices=PHASES, default="focus", help="假番茄的阶段")
    parser.add_argument("--banner", choices=BANNERS, help="一开始就显示的横幅")
    args = parser.parse_args()

    port = open_port(args.port)
    if args.off:
        port.write(b"OFF\n")
        port.flush()
        return

    page = args.page
    banner = BANNERS.get(args.banner, "B k=none")
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
            send(port, timer_line(args.phase, start))
            send(port, banner)
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
                if banner != "B k=none":
                    banner = "B k=none"
                    send(port, banner)
                else:
                    page = next_page(page)
                send_page(port, page)

        time.sleep(0.02)


if __name__ == "__main__":
    main()
