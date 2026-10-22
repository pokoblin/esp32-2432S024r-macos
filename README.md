# Sysmon: a Mac status screen on an ESP32-2432S024R

**English** | [简体中文](docs/readme/README.zh-CN.md) | [繁體中文](docs/readme/README.zh-TW.md) | [日本語](docs/readme/README.ja.md) | [한국어](docs/readme/README.ko.md) | [Español](docs/readme/README.es.md) | [Français](docs/readme/README.fr.md) | [Deutsch](docs/readme/README.de.md) | [Português (Brasil)](docs/readme/README.pt-BR.md) | [Русский](docs/readme/README.ru.md)

Turn an ESP32-2432S024R (a 2.4" ST7789 board, a.k.a. "Cheap Yellow Display") into a little status screen next to your monitor. At a glance you see CPU, memory pressure and network speed, how much of your Claude and ChatGPT subscription limits is left, and a pomodoro timer that reminds you to take breaks, stand up and drink water.

The menu bar app **Sysmon** samples your Mac every 2 seconds and sends the data to the board over USB serial; the board draws the rings and charts. No Wi-Fi, and no ports are opened on your Mac.

![Sysmon screen next to a monitor](docs/images/sysmon-preview.jpg)

<sub>Illustrations are drawn from the firmware's real layout and colors; the data is made up.</sub>

> **Language note:** the Mac app comes in 10 languages. The board itself currently shows Chinese text only; the pictures in this README show an English rendering of the same screens.

## Screens

Portrait 240×320, dark background. Four screens: System, Pomodoro, Claude usage and ChatGPT usage. A reminder banner can cover any of them.

![The four screens](docs/images/screens.jpg)

### System

- **Top:** CPU and memory-pressure rings. CPU turns yellow at 50% and red at 80%. The memory ring follows macOS's memory-pressure level (normal / warning / critical), just like Activity Monitor.
- **Bottom:** current download and upload speed, plus a two-color chart of the last 5 minutes. The chart scales to the 5-minute peak.

### Pomodoro

- A big ring shows how much of the current session is left, with the remaining time, the phase and when it ends. Focus is tomato red, short break green, long break blue; paused or not started is gray.
- Below: dots for this round (4 focus sessions by default), e.g. "#2 · 2 more until long break", and today's tally, e.g. "5 done · 2h 05m".
- Defaults: 25 min focus, 5 min short break, 15 min long break after every 4th focus. All adjustable; changes apply from the next session.
- Only focus needs a manual start: a finished focus rolls straight into a break, and a finished break waits for you.
- Start, pause and resume with one global shortcut or from the menu; the menu also has Skip and Reset Round. Skipping a focus abandons it and it isn't counted.
- The timer runs on real time, so it keeps going while you're away, the screen is locked or the Mac sleeps. Today's tally resets at midnight and survives restarts.
- While you're focusing, the other screens show a thin 3 px tomato-red progress line at the very top (gray while paused).

### Claude and ChatGPT usage

- A big ring for the 5-hour limit with the time until it resets, and bars for the weekly limit ("This week · resets Thu 14:00"). Claude also shows its per-model weekly limits when the API reports them.
- Same color thresholds as CPU. The footer shows the plan (Max, Plus…) and how fresh the data is.
- Stale data is always marked: "Expired" when the sign-in has run out, "Couldn't read" when a request failed, and "--" when a window has already reset.

### Reminder banners

![The four reminder banners](docs/images/banners.jpg)

Whatever screen you're on, a banner takes over the whole screen and the RGB light on the back of the board breathes in the same color (you can turn the light off). Tap the board or press the switch-screen shortcut to dismiss it.

| Banner | When | Color | Goes away by itself |
|---|---|---|---|
| Focus done | A focus session ends and the break starts; shows the break countdown and any reminders held back during focus | green | when the break ends |
| Break over | The break ends | red | when you start the next focus |
| Stand up | 50 minutes of actual computer use | orange | after 5 minutes away |
| Drink water | 60 minutes of computer use | blue | no, tap to dismiss |

- "Computer use" means keyboard or mouse activity. Idle time and a locked or sleeping screen add up as time away: 5 minutes away resets the stand-up timer, 30 minutes resets the water timer.
- No banners during focus (including paused): they are held and folded into the "Focus done" banner.
- One banner at a time, in the order shown in the table.

### Switching screens and turning off

- Order: System → Pomodoro → Claude → ChatGPT. Tap anywhere on the board or press the global shortcut. While a banner is showing, the same action dismisses it instead.
- Screens turned off in Settings are skipped. The page dots in the top-right corner show where you are.
- The screen and the light go dark as soon as the display sleeps, the screen locks, you switch users or the Mac sleeps, and come back automatically. About 10 seconds after Sysmon quits or the cable is unplugged, the screen turns off.

## The menu bar app

- The icon is an ESP32 module; it gets a slash while no board is connected.
- The menu has the connection status, the pomodoro actions that make sense right now, Settings, About and Quit.
- Settings has four tabs:
  - **General:** the switch-screen shortcut, the RGB light, the app language (System Default or one of 10 languages) and Launch at Login.
  - **Pomodoro:** the pomodoro screen, the start/pause shortcut, durations and sessions per round.
  - **Reminders:** stand-up and water reminders and their intervals.
  - **Usage:** the Claude and ChatGPT usage screens with their status, and where the data comes from.
- Global shortcuts use Carbon hot keys, so no Accessibility permission is needed. Detecting whether you're at the computer reads the system idle time, which needs no permission either.
- It finds the board by the WCH (CH340) USB vendor ID and reconnects after replugging. Opening or closing the port never resets the board.
- CPU usage stays close to 0%.

<!-- Screenshots of the menu and the Settings window go here, e.g. docs/images/macos-menu.png and docs/images/macos-settings.png -->

### Where usage data comes from

Sysmon borrows the sign-ins already on your Mac, read-only:

- **Claude:** the Claude Code credentials in the login keychain (item `Claude Code-credentials`, read through `/usr/bin/security`, so no permission prompt), sent to Anthropic's usage endpoint.
- **ChatGPT:** Codex's `~/.codex/auth.json`, sent to ChatGPT's usage endpoint.

Sysmon never renews these sign-ins and never writes the keychain or `auth.json`, so it can't sign you out. The catch: if you don't use Claude Code or Codex for a while, the sign-in expires and the screen keeps the last numbers, marked "Expired". To fix it, run `claude` once in a terminal, or open Codex once; new numbers show up within 2 minutes. Usage is fetched every 2 minutes, and not while the screen is off.

Neither endpoint is documented and either may change. If one can't be parsed, only that screen shows "Couldn't read".

## Requirements

| Item | Requirement |
|---|---|
| Board | ESP32-2432S024R (ESP32-D0WD-V3, 4 MB flash, ST7789 240×320, CH340 serial) |
| Mac | macOS 14 or later |
| Firmware toolchain | [PlatformIO](https://platformio.org/) |
| Mac toolchain | Xcode Command Line Tools (Swift 6) |

## Quick start

```bash
git clone git@github.com:pokoblin/esp32-2432S024r-macos.git
cd esp32-2432S024r-macos
```

### 1. Flash the firmware

```bash
cd sysmon/firmware
pio run -e esp32dev -t upload
```

`platformio.ini` uses `/dev/cu.usbserial-114110`; change it to your port (`ls /dev/cu.usbserial-*`). Quit Sysmon before flashing, or the port will be busy.

> Through a USB hub this board fails to flash at 921600 and 460800, so `upload_speed` is fixed at 115200.

### 2. Install the menu bar app

```bash
cd sysmon/macos
bash scripts/bundle.sh
open ~/Applications/Sysmon.app
```

`bundle.sh` builds a release, creates `Sysmon.app`, signs it ad hoc and installs it into `~/Applications`. Turn on "Launch at Login" in Settings if you like.

## Development

Run the tests:

```bash
cd sysmon/firmware && pio test -e native
cd sysmon/macos && swift test
```

Drive the board without Sysmon (needs pyserial; PlatformIO's Python already has it):

```bash
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110                    # sys / pomo / cl / gpt with --page
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle            # rotate screens automatically
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page pomo --phase paused
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --banner done      # done / brk / sit / water
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
```

Banner titles use a tiny font that contains only the characters they need (the firmware already uses over 90% of its flash). After changing the titles in `lib/sysmon_core/banner_titles.h`, regenerate it; the font is Source Han Sans CN Bold (SIL Open Font License 1.1) and must be installed locally:

```bash
swift sysmon/tools/make_banner_font.swift ~/Library/Fonts/SourceHanSansCN-Bold.otf 24
```

The README pictures are generated by `docs/images/make_preview.py` and `docs/images/make_screens.py`; the commands are in each script's header.

### Serial protocol

115200 8N1, plain text, one record per line:

```
S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640
OFF
```

| Field | Meaning |
|---|---|
| `cpu` | CPU usage, 0–100 |
| `mem` | memory pressure percent, 0–100 |
| `lvl` | memory pressure level: 1 normal, 2 warning, 4 critical |
| `rx` / `tx` | download / upload speed, bytes per second |
| `OFF` | turn the screen off until the next `S` line |

The firmware ignores unknown lines and fields. Pages, usage, pomodoro and banners use the `P`, `U`, `T` and `B` lines, and the board sends `TAP` when tapped: see the header comments of `usage_protocol.h`, `timer_protocol.h` and `Protocol.swift`.

## Repository layout

```
sysmon/
  firmware/            ESP32 firmware (PlatformIO + Arduino + LovyanGFX)
    lib/sysmon_core/   pure logic: protocol parsing, screen-off state, chart history, copy, tap debounce, colors, breathing curve
    src/               display config, drawing, RGB light, generated banner font, main loop
    test/              unit tests that run on the computer
  macos/               menu bar app (SwiftPM)
    Sources/SysmonCore/  CPU/memory/network sampling, serial, device discovery, usage credentials and parsing,
                         page order, pomodoro and reminder rules, localization
    Sources/Sysmon/      SwiftUI menu bar UI, Settings, About, global shortcuts
    scripts/bundle.sh    build and install the .app
  tools/fake_feed.py   fake data for the board, no Mac app needed
  tools/make_banner_font.swift  generates the banner title font
hw_probe/              hardware probe firmware: display driver, touch chip and pins
touch_diag/            raw XPT2046 touch diagnostics
touch_test/            touch calibration and drawing test; board.h is the verified display config
.superpowers/          UI mockups from the design phase
docs/images/           README pictures and their generators
docs/readme/           translated READMEs
```

## Hardware notes

- The display controller is an **ST7789**, not an ILI9341. With `Panel_ILI9341` the picture comes out transposed and mirrored.
- LovyanGFX settings: `rgb_order=false` (true swaps red and blue), `invert=false`, rotation 0.
- Backlight on GPIO27, active high. The display's MISO isn't connected, so its ID can't be read.
- The RGB LED on the back is common-anode, active low: GPIO4 red, GPIO16 blue, GPIO17 green (blue and green are the other way round from what most CYD notes say).
- The CH340 drives EN and GPIO0 through DTR/RTS. Sysmon clears both right after opening the port and turns off `HUPCL`, so opening or closing the port never resets the board.
