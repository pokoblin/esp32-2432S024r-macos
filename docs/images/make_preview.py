"""生成 README 用的示意图 HTML：显示器右边缘 + 贴在旁边的 ESP32 副屏。
屏幕内容按固件 sysmon/firmware/src/ui.cpp 的坐标（240×320）和配色画，数据是编的。

重新生成：
    python3 docs/images/make_preview.py /tmp/preview.html
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
        --force-device-scale-factor=2 --window-size=1200,820 --screenshot=/tmp/preview.png file:///tmp/preview.html
    sips -s format jpeg -s formatOptions 88 /tmp/preview.png --out docs/images/sysmon-preview.jpg
"""
import math
import random
import sys

random.seed(7)

# ---- 150 个点的网速历史（字节/秒），最新的在最后 ----
rx, tx = [], []
for i in range(150):
    t = i / 149
    base = 2.0 + 9.5 * math.exp(-((t - 0.38) / 0.11) ** 2) + 12.0 * math.exp(-((t - 0.93) / 0.07) ** 2)
    rx.append(max(0.05, base + random.uniform(-0.6, 0.6)) * 1048576)
    tx.append(max(0.02, 0.5 + 0.9 * math.exp(-((t - 0.62) / 0.07) ** 2) + random.uniform(-0.15, 0.15)) * 1048576)
rx[-1] = 13002342
tx[-1] = 901120
for k in range(1, 6):  # 末尾几个点平滑过渡到当前值
    rx[-1 - k] = rx[-6] + (rx[-1] - rx[-6]) * (5 - k) / 5
peak = max(rx + tx)

X0, X1, PEAK_Y, BOTTOM = 12, 228, 208, 294


def px(i):
    return X1 - (149 - i) * (X1 - X0) / 149


def py(v):
    return BOTTOM - v * (BOTTOM - PEAK_Y) / peak


def fmt(bps):
    v = bps / 1048576
    unit = "MB/s"
    if v >= 999.5:
        v /= 1024
        unit = "GB/s"
    f = "%.2f" if v < 9.995 else "%.1f" if v < 99.95 else "%.0f"
    return f % v, unit


rx_pts = " ".join(f"{px(i):.1f},{py(v):.1f}" for i, v in enumerate(rx))
tx_pts = " ".join(f"{px(i):.1f},{py(v):.1f}" for i, v in enumerate(tx))
fill_pts = f"{X0},{BOTTOM} {rx_pts} {X1},{BOTTOM}"


def ring(cx, pct, color, num_color, label):
    r = 40
    c = 2 * math.pi * r
    return f"""
    <circle cx="{cx}" cy="60" r="{r}" fill="none" stroke="#1c2026" stroke-width="10"/>
    <circle cx="{cx}" cy="60" r="{r}" fill="none" stroke="{color}" stroke-width="10" stroke-linecap="round"
            stroke-dasharray="{c * pct / 100:.2f} {c:.2f}" transform="rotate(-90 {cx} 60)"/>
    <text x="{cx}" y="69" text-anchor="middle" class="num" fill="{num_color}">{pct}</text>
    <text x="{cx}" y="124" text-anchor="middle" class="lbl">{label}</text>"""


rxn, rxu = fmt(rx[-1])
txn, txu = fmt(tx[-1])
pkn, pku = fmt(peak)

screen = f"""
<svg viewBox="0 0 240 320" width="420" height="560" xmlns="http://www.w3.org/2000/svg">
  <style>
    .num {{ font: 700 25px 'Helvetica Neue', Helvetica, Arial, sans-serif; }}
    .big {{ font: 700 25px 'Helvetica Neue', Helvetica, Arial, sans-serif; }}
    .lbl {{ font: 400 11.5px 'PingFang SC', sans-serif; fill: #8a9099; }}
    .dim {{ font: 400 9.5px 'PingFang SC', sans-serif; fill: #5c626b; }}
  </style>
  <rect width="240" height="320" fill="#0b0d10"/>
  {ring(64, 62, "#ffcc00", "#e8eaed", "CPU %")}
  {ring(176, 51, "#34c759", "#34c759", "内存压力 %")}
  <line x1="12" y1="134.5" x2="228" y2="134.5" stroke="#1c2026"/>
  <text x="12" y="154" class="lbl">↓ 下载</text>
  <text x="228" y="154" text-anchor="end" class="lbl">↑ 上传</text>
  <text x="12" y="185" class="big" fill="#64d2ff">{rxn}<tspan class="lbl" dx="3">{rxu}</tspan></text>
  <text x="228" y="185" text-anchor="end" class="big" fill="#ff9f0a">{txn}<tspan class="lbl" dx="3">{txu}</tspan></text>
  <line x1="12" y1="{PEAK_Y}.5" x2="228" y2="{PEAK_Y}.5" stroke="#1c2026" stroke-dasharray="3 3"/>
  <text x="228" y="205" text-anchor="end" class="dim">峰值 {pkn} {pku}</text>
  <line x1="12" y1="{BOTTOM}.5" x2="228" y2="{BOTTOM}.5" stroke="#1c2026"/>
  <polygon points="{fill_pts}" fill="#182b34"/>
  <polyline points="{rx_pts}" fill="none" stroke="#64d2ff" stroke-width="1.6" stroke-linejoin="round"/>
  <polyline points="{tx_pts}" fill="none" stroke="#ff9f0a" stroke-width="1.6" stroke-linejoin="round"/>
  <text x="12" y="309" class="dim">5 分钟前</text>
  <text x="228" y="309" text-anchor="end" class="dim">现在</text>
</svg>"""

# 菜单栏里的 Sysmon 图标，和 BoardIcon.swift 同样的画法（18×18）
icon = """
<svg viewBox="0 0 18 18" width="18" height="18">
  <rect x="4.5" y="1.5" width="9" height="15" rx="1.2" fill="none" stroke="#fff" stroke-width="1.2"/>
  <polyline points="6.5,5.5 6.5,3.5 9,3.5 9,5.5 11.5,5.5 11.5,3.5" fill="none" stroke="#fff" stroke-width="1"/>
  <rect x="6" y="7.5" width="6" height="7.5" rx="0.6" fill="#fff"/>
  <g fill="#fff">
    <rect x="1.5" y="7.5" width="2.5" height="1"/><rect x="1.5" y="9.83" width="2.5" height="1"/>
    <rect x="1.5" y="12.16" width="2.5" height="1"/><rect x="1.5" y="14.5" width="2.5" height="1"/>
    <rect x="14" y="7.5" width="2.5" height="1"/><rect x="14" y="9.83" width="2.5" height="1"/>
    <rect x="14" y="12.16" width="2.5" height="1"/><rect x="14" y="14.5" width="2.5" height="1"/>
  </g>
</svg>"""

holes = "".join(
    f'<div class="hole" style="left:{x}px;top:{y}px"></div>' for x, y in [(14, 14), (432, 14), (14, 648), (432, 648)]
)

html = f"""<!doctype html>
<html><head><meta charset="utf-8"><style>
  html, body {{ margin: 0; width: 1200px; height: 820px; overflow: hidden; }}
  body {{
    background: radial-gradient(ellipse at 70% 40%, #3a3f47 0%, #24272c 45%, #141518 100%);
    font-family: -apple-system, 'PingFang SC', sans-serif; position: relative;
  }}
  /* 显示器右边缘 */
  .monitor {{
    position: absolute; left: -420px; top: 40px; width: 900px; height: 900px;
    background: #0d0e10; border-radius: 22px; padding: 14px;
    box-shadow: 0 30px 80px rgba(0,0,0,.6), inset 0 0 0 1px #2a2d31;
  }}
  .display {{
    width: 100%; height: 100%; border-radius: 8px; overflow: hidden; position: relative;
    background:
      radial-gradient(ellipse at 20% 80%, #ff7a59 0%, transparent 45%),
      radial-gradient(ellipse at 70% 30%, #6b4bff 0%, transparent 50%),
      radial-gradient(ellipse at 90% 90%, #1e9bff 0%, transparent 45%),
      linear-gradient(135deg, #2a1a5e, #0b1a3a);
  }}
  .menubar {{
    position: absolute; top: 0; left: 0; right: 0; height: 30px;
    background: rgba(20, 20, 28, .45); backdrop-filter: blur(20px);
    display: flex; justify-content: flex-end; align-items: center; gap: 16px; padding-right: 18px;
    color: #fff; font-size: 13.5px; font-weight: 500;
  }}
  .menubar svg {{ display: block; }}
  .sysmon-icon {{ background: rgba(255,255,255,.22); border-radius: 5px; padding: 3px 5px; }}
  /* 副屏电路板 */
  .board {{
    position: absolute; left: 640px; top: 70px; width: 460px; height: 680px;
    background: linear-gradient(160deg, #f3c536 0%, #e2ab17 55%, #c9930d 100%);
    border-radius: 14px;
    box-shadow: 0 40px 70px rgba(0,0,0,.55), 0 8px 18px rgba(0,0,0,.35), inset 0 0 0 2px rgba(255,255,255,.18);
    transform: perspective(1600px) rotateY(-9deg); transform-origin: left center;
  }}
  .hole {{
    position: absolute; width: 14px; height: 14px; border-radius: 50%;
    background: #1b1c1f; box-shadow: 0 0 0 4px #d8d9db, 0 0 0 5px #a7a8aa;
  }}
  .glass {{
    position: absolute; left: 10px; top: 42px; width: 440px; height: 596px;
    background: #050607; border-radius: 6px;
    box-shadow: inset 0 0 0 1px #2b2e33;
  }}
  .glass svg {{
    position: absolute; left: 10px; top: 18px; border-radius: 2px;
    box-shadow: 0 0 40px rgba(100, 210, 255, .08);
  }}
  .glare {{
    position: absolute; inset: 0; border-radius: 6px; pointer-events: none;
    background: linear-gradient(115deg, rgba(255,255,255,.10) 0%, rgba(255,255,255,0) 38%);
  }}
  .usb {{
    position: absolute; left: 196px; bottom: -6px; width: 68px; height: 16px;
    background: linear-gradient(#d5d6d8, #8e9092); border-radius: 6px;
    box-shadow: inset 0 0 0 3px #b3b4b6;
  }}
  .silk {{ position: absolute; color: rgba(255,255,255,.75); font: 700 13px Menlo, monospace; letter-spacing: 1px; }}
  .cable {{
    position: absolute; left: 855px; top: 752px; width: 22px; height: 120px;
    background: linear-gradient(90deg, #1a1b1d, #3a3c40, #1a1b1d); border-radius: 6px;
  }}
</style></head><body>
  <div class="monitor"><div class="display">
    <div class="menubar">
      <span class="sysmon-icon">{icon}</span>
      <span>10月21日 周三 14:32</span>
    </div>
  </div></div>
  <div class="cable"></div>
  <div class="board">
    {holes}
    <div class="silk" style="left:150px;top:16px">ESP32-2432S024</div>
    <div class="glass">{screen}<div class="glare"></div></div>
    <div class="usb"></div>
  </div>
</body></html>"""

open(sys.argv[1], "w").write(html)
