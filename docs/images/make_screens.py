"""生成 README 用的两张屏幕示意图 HTML：四块屏并排（screens），四种提醒横幅并排（banners）。
屏幕内容按固件 sysmon/firmware/src/ui.cpp 的坐标（240×320，内容整体下移 4px）和配色画，文字用英文，数据是编的。
README 的各语言版本共用这两张图。

重新生成：
    python3 docs/images/make_screens.py screens /tmp/screens.html
    python3 docs/images/make_screens.py banners /tmp/banners.html
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
        --force-device-scale-factor=2 --window-size=1440,560 --screenshot=/tmp/screens.png file:///tmp/screens.html
    sips -s format jpeg -s formatOptions 88 /tmp/screens.png --out docs/images/screens.jpg
（banners 同理，输出 docs/images/banners.jpg）
"""
import math
import random
import sys

BG, TRACK, TEXT, LABEL, DIM = "#0b0d10", "#1c2026", "#e8eaed", "#8a9099", "#5c626b"
GREEN, YELLOW, BLUE, ORANGE, TOMATO = "#34c759", "#ffcc00", "#64d2ff", "#ff9f0a", "#ff6347"
INSET = 4  # 顶边留给番茄进度线

STYLE = """
  .num { font: 700 25px 'Helvetica Neue', Helvetica, Arial, sans-serif; }
  .big { font: 700 36px 'Helvetica Neue', Helvetica, Arial, sans-serif; }
  .mid { font: 700 26px 'Helvetica Neue', Helvetica, Arial, sans-serif; }
  .pct { font: 700 13px 'Helvetica Neue', Helvetica, Arial, sans-serif; }
  .brand { font: 700 14px 'Helvetica Neue', Helvetica, Arial, sans-serif; }
  .lbl { font: 400 11.5px -apple-system, 'Helvetica Neue', sans-serif; fill: #8a9099; }
  .txt { font: 400 13px -apple-system, 'Helvetica Neue', sans-serif; }
  .dim { font: 400 9.5px -apple-system, 'Helvetica Neue', sans-serif; fill: #5c626b; }
  .title { font: 700 23px -apple-system, 'Helvetica Neue', sans-serif; }
"""


def arc(cx, cy, r, width, pct, color):
    c = 2 * math.pi * r
    track = f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{TRACK}" stroke-width="{width}"/>'
    if pct <= 0:
        return track
    return track + (
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{color}" stroke-width="{width}" '
        f'stroke-linecap="round" stroke-dasharray="{c * pct / 100:.2f} {c:.2f}" transform="rotate(-90 {cx} {cy})"/>'
    )


def dots(index, count, y=9 + INSET):
    return "".join(
        f'<circle cx="{225 - (count - i) * 10}" cy="{y}" r="3" fill="{LABEL if i == index else TRACK}"/>'
        for i in range(1, count + 1)
    )


def focus_line(done_pct):
    return f'<rect width="240" height="3" fill="{TRACK}"/><rect width="{240 * done_pct / 100:.0f}" height="3" fill="{TOMATO}"/>'


def tone(v):
    return GREEN if v < 50 else YELLOW if v < 80 else "#ff453a"


def svg(body, bg=BG):
    return (f'<svg viewBox="0 0 240 320" width="300" height="400" xmlns="http://www.w3.org/2000/svg">'
            f'<style>{STYLE}</style><rect width="240" height="320" fill="{bg}"/>{body}</svg>')


# ---- 系统状态屏 ----
def system_screen():
    random.seed(7)
    rx, tx = [], []
    for i in range(150):
        t = i / 149
        base = 2.0 + 9.5 * math.exp(-((t - 0.38) / 0.11) ** 2) + 12.0 * math.exp(-((t - 0.93) / 0.07) ** 2)
        rx.append(max(0.05, base + random.uniform(-0.6, 0.6)))
        tx.append(max(0.02, 0.5 + 0.9 * math.exp(-((t - 0.62) / 0.07) ** 2) + random.uniform(-0.15, 0.15)))
    peak = max(rx + tx)
    x = lambda i: 228 - (149 - i) * 216 / 149
    y = lambda v: 294 - v * 86 / peak
    rx_pts = " ".join(f"{x(i):.1f},{y(v):.1f}" for i, v in enumerate(rx))
    tx_pts = " ".join(f"{x(i):.1f},{y(v):.1f}" for i, v in enumerate(tx))
    ry = 60 + INSET

    def ring(cx, pct, color, num_color, label):
        return (arc(cx, ry, 40, 10, pct, color)
                + f'<text x="{cx}" y="{ry + 9}" text-anchor="middle" class="num" fill="{num_color}">{pct}</text>'
                + f'<text x="{cx}" y="{124 + INSET}" text-anchor="middle" class="lbl">{label}</text>')

    return svg(f"""
      {focus_line(50)}{dots(1, 4)}
      {ring(64, 62, YELLOW, TEXT, "CPU %")}
      {ring(176, 51, GREEN, GREEN, "Memory pressure %")}
      <line x1="12" y1="134.5" x2="228" y2="134.5" stroke="{TRACK}"/>
      <text x="12" y="154" class="lbl">↓ Download</text>
      <text x="228" y="154" text-anchor="end" class="lbl">↑ Upload</text>
      <text x="12" y="185" class="num" fill="{BLUE}">12.4<tspan class="lbl" dx="3">MB/s</tspan></text>
      <text x="228" y="185" text-anchor="end" class="num" fill="{ORANGE}">0.86<tspan class="lbl" dx="3">MB/s</tspan></text>
      <line x1="12" y1="208.5" x2="228" y2="208.5" stroke="{TRACK}" stroke-dasharray="3 3"/>
      <text x="228" y="205" text-anchor="end" class="dim">Peak {peak:.1f} MB/s</text>
      <line x1="12" y1="294.5" x2="228" y2="294.5" stroke="{TRACK}"/>
      <polygon points="12,294 {rx_pts} 228,294" fill="#182b34"/>
      <polyline points="{rx_pts}" fill="none" stroke="{BLUE}" stroke-width="1.6" stroke-linejoin="round"/>
      <polyline points="{tx_pts}" fill="none" stroke="{ORANGE}" stroke-width="1.6" stroke-linejoin="round"/>
      <text x="12" y="309" class="dim">5 min ago</text>
      <text x="228" y="309" text-anchor="end" class="dim">now</text>""")


# ---- 用量屏 ----
def bar(y, label, v):
    w = 216 * v / 100
    return (f'<text x="12" y="{y + 11}" class="lbl">{label}</text>'
            f'<text x="228" y="{y + 12}" text-anchor="end" class="pct" fill="{TEXT if v < 50 else tone(v)}">{v}%</text>'
            f'<rect x="12" y="{y + 17}" width="216" height="8" rx="4" fill="{TRACK}"/>'
            f'<rect x="12" y="{y + 17}" width="{max(w, 8):.0f}" height="8" rx="4" fill="{tone(v)}"/>')


def usage_screen(brand, color, index, h5, reset, bars, plan, updated):
    rows = "".join(bar(194 + 36 * i, label, v) for i, (label, v) in enumerate(bars))
    return svg(f"""
      {focus_line(50)}
      <text x="12" y="{15 + INSET}" class="brand" fill="{color}">{brand}</text>{dots(index, 4)}
      {arc(120, 96 + INSET, 58, 14, h5, tone(h5))}
      <text x="120" y="{90 + INSET + 13}" text-anchor="middle" class="big" fill="{TEXT if h5 < 50 else tone(h5)}">{h5}</text>
      <text x="120" y="{126 + 4}" text-anchor="middle" class="lbl">5-hour %</text>
      <text x="120" y="{176 + 3}" text-anchor="middle" class="dim">{reset}</text>
      <line x1="12" y1="{182 + INSET}.5" x2="228" y2="{182 + INSET}.5" stroke="{TRACK}"/>
      {rows}
      <text x="12" y="309" class="dim">{plan}</text>
      <text x="228" y="309" text-anchor="end" class="dim">{updated}</text>""")


# ---- 番茄屏 ----
def pomodoro_screen():
    cy = 96 + INSET
    round_dots = ""
    for i in range(4):
        x = 120 - 27 + i * 18
        if i == 0:
            round_dots += f'<circle cx="{x}" cy="{204}" r="5" fill="{TOMATO}"/>'
        elif i == 1:
            round_dots += f'<circle cx="{x}" cy="{204}" r="4" fill="none" stroke="{TOMATO}" stroke-width="2"/>'
        else:
            round_dots += f'<circle cx="{x}" cy="{204}" r="5" fill="{TRACK}"/>'
    return svg(f"""
      <text x="12" y="{16 + INSET}" class="brand" fill="{TOMATO}">Pomodoro</text>{dots(2, 4)}
      {arc(120, cy, 58, 14, 50, TOMATO)}
      <text x="120" y="{cy + 2}" text-anchor="middle" class="mid" fill="{TEXT}">12:34</text>
      <text x="120" y="{126 + 4}" text-anchor="middle" class="lbl" fill="{TOMATO}" style="fill:{TOMATO}">Focus</text>
      <text x="120" y="{176 + 3}" text-anchor="middle" class="dim">Ends 14:52</text>
      <line x1="12" y1="{182 + INSET}.5" x2="228" y2="{182 + INSET}.5" stroke="{TRACK}"/>
      {round_dots}
      <text x="120" y="{224 + 3}" text-anchor="middle" class="dim">#2 · 2 more until long break</text>
      <text x="12" y="{262 + 4}" class="lbl">Today</text>
      <text x="228" y="{262 + 4}" text-anchor="end" class="lbl"><tspan class="num" style="font-size:18px" fill="{TEXT}">5</tspan> done · 2h 05m</text>
      <text x="12" y="309" class="dim">Press shortcut to pause</text>""")


# ---- 横幅 ----
def mix(hex_color, pct):
    a = [int(hex_color[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(BG[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{(x * pct + y * (100 - pct)) // 100:02x}" for x, y in zip(a, b))


def banner(color, title, detail, hint, clock=None, extras=None):
    done = clock is not None
    ty = 84 if done else 116
    body = (f'<text x="120" y="{ty + 8}" text-anchor="middle" class="title" fill="{color}">{title}</text>'
            f'<text x="120" y="{ty + 36 + 5}" text-anchor="middle" class="txt" fill="#d6dbe0">{detail}</text>')
    if done:
        body += f'<text x="120" y="{176 + 13}" text-anchor="middle" class="big" fill="{TEXT}">{clock}</text>'
        body += f'<line x1="40" y1="214.5" x2="200" y2="214.5" stroke="{mix(color, 40)}"/>'
        body += f'<text x="120" y="{234 + 5}" text-anchor="middle" class="txt" fill="{TEXT}">{extras}</text>'
    body += f'<text x="120" y="309" text-anchor="middle" class="dim" style="fill:{mix("#e8eaed", 55)}">{hint}</text>'
    return svg(body, bg=mix(color, 18))


def page(cells, caption_color="#c8ccd2"):
    items = "".join(
        f'<figure><div class="frame">{s}</div><figcaption>{c}</figcaption></figure>' for s, c in cells
    )
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
  html, body {{ margin: 0; width: 1440px; height: 560px; overflow: hidden; }}
  body {{ background: radial-gradient(ellipse at 50% 30%, #2c3036 0%, #17191c 70%);
         display: flex; justify-content: center; align-items: center; gap: 28px;
         font-family: -apple-system, 'Helvetica Neue', sans-serif; }}
  figure {{ margin: 0; display: flex; flex-direction: column; align-items: center; gap: 16px; }}
  .frame {{ padding: 12px; background: #050607; border-radius: 10px;
           box-shadow: 0 0 0 6px #e2ab17, 0 24px 50px rgba(0,0,0,.55); }}
  .frame svg {{ display: block; border-radius: 2px; }}
  figcaption {{ color: {caption_color}; font-size: 17px; font-weight: 600; letter-spacing: .2px; }}
</style></head><body>{items}</body></html>"""


def screens_page():
    claude = usage_screen("Claude", "#d97757", 3, 42, "Resets in 2h 13m",
                          [("This week · resets Thu 14:00", 67), ("This week Fable", 12)], "Max", "Updated 1 min ago")
    chatgpt = usage_screen("ChatGPT", "#10a37f", 4, 6, "Resets in 4h 40m",
                           [("This week · resets Tue 09:00", 35)], "Plus", "Updated 3 min ago")
    return page([(system_screen(), "System"), (pomodoro_screen(), "Pomodoro"),
                 (claude, "Claude usage"), (chatgpt, "ChatGPT usage")])


def banners_page():
    return page([
        (banner(GREEN, "Focus done", "Take a 5 min break", "Tap to dismiss", "04:59",
                "Also stand up and drink some water"), "Focus done"),
        (banner(TOMATO, "Break over", "Time for the next focus", "Press shortcut to start · Tap to dismiss"),
         "Break over"),
        (banner(ORANGE, "Time to stand up", "52 min at the computer", "Tap to dismiss · Clears after 5 min away"),
         "Stand up"),
        (banner(BLUE, "Drink some water", "Last reminder 60 min ago", "Tap to dismiss"), "Drink water"),
    ])


if __name__ == "__main__":
    kind, out = sys.argv[1], sys.argv[2]
    open(out, "w").write({"screens": screens_page, "banners": banners_page}[kind]())
