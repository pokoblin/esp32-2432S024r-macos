<p align="center"><img src="../images/icon.png" width="128" alt="Sysmon icon"></p>

# Sysmon: ESP32-2432S024R로 만드는 Mac 상태 화면

[English](../../README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | **한국어** | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português (Brasil)](README.pt-BR.md) | [Русский](README.ru.md)

ESP32-2432S024R(2.4인치 ST7789 보드, 일명 "Cheap Yellow Display")을 모니터 옆에 두는 작은 상태 화면으로 만들어 보세요. CPU, 메모리 압력, 네트워크 속도, Claude와 ChatGPT 구독 한도가 얼마나 남았는지, 그리고 휴식하고, 일어나고, 물 마시라고 알려 주는 뽀모도로 타이머를 한눈에 볼 수 있습니다.

메뉴 막대 앱 **Sysmon**이 2초마다 Mac의 상태를 측정해 USB 시리얼로 보드에 보내고, 보드는 링과 차트를 그립니다. Wi-Fi는 쓰지 않고, Mac의 포트도 열지 않습니다.

![모니터 옆에 놓인 Sysmon 화면](../images/sysmon-preview.jpg)

<sub>그림은 펌웨어의 실제 레이아웃과 색상으로 그렸으며, 데이터는 임의로 만든 것입니다.</sub>

> **언어 안내:** Mac 앱은 10개 언어를 지원합니다. 보드 자체는 현재 중국어 텍스트만 표시하며, 이 README의 그림에는 같은 화면을 영어로 옮겨 그려 넣었습니다.

## 화면

세로 240×320, 어두운 배경. 시스템, 뽀모도로, Claude 사용량, ChatGPT 사용량의 네 가지 화면이 있습니다. 알림 배너는 어느 화면 위에든 뜰 수 있습니다.

![네 가지 화면](../images/screens.jpg)

### 시스템

- **위쪽:** CPU와 메모리 압력 링. CPU는 50%에서 노란색, 80%에서 빨간색이 됩니다. 메모리 링은 활성 상태 보기와 마찬가지로 macOS의 메모리 압력 수준(정상 / 주의 / 위험)을 따릅니다.
- **아래쪽:** 현재 다운로드·업로드 속도와 최근 5분간의 2색 차트. 차트는 5분 동안의 최고치에 맞춰 크기가 조정됩니다.

### 뽀모도로

- 큰 링에 현재 세션이 얼마나 남았는지가 남은 시간, 단계, 종료 시각과 함께 표시됩니다. 집중은 토마토 빨강, 짧은 휴식은 초록, 긴 휴식은 파랑이고, 일시 정지나 시작 전에는 회색입니다.
- 아래에는 이번 라운드를 나타내는 점(기본 집중 4회)과 "#2 · 2 more until long break"(#2 · 긴 휴식까지 2회 남음) 같은 문구, 그리고 "5 done · 2h 05m"(5회 완료 · 2시간 05분) 같은 오늘의 집계가 표시됩니다.
- 기본값: 집중 25분, 짧은 휴식 5분, 집중 4회마다 긴 휴식 15분. 모두 조정할 수 있으며, 변경 사항은 다음 세션부터 적용됩니다.
- 수동으로 시작해야 하는 것은 집중뿐입니다. 집중이 끝나면 바로 휴식으로 넘어가고, 휴식이 끝나면 사용자를 기다립니다.
- 하나의 전역 단축키 또는 메뉴로 시작, 일시 정지, 재개할 수 있으며, 메뉴에는 건너뛰기와 라운드 초기화도 있습니다. 집중을 건너뛰면 그 세션은 포기한 것으로 보아 집계되지 않습니다.
- 타이머는 실제 시간을 기준으로 동작하므로 자리를 비웠거나, 화면이 잠겼거나, Mac이 잠자기 상태여도 계속 흘러갑니다. 오늘의 집계는 자정에 초기화되며 재시작해도 유지됩니다.
- 집중하는 동안 다른 화면들의 맨 위에는 3px 두께의 토마토 빨강 진행선이 표시됩니다(일시 정지 중에는 회색).

### Claude와 ChatGPT 사용량

- 5시간 한도를 나타내는 큰 링과 초기화까지 남은 시간, 그리고 주간 한도 막대("This week · resets Thu 14:00", 이번 주 · 목요일 14:00에 초기화)가 표시됩니다. API가 모델별 주간 한도를 알려 주면 Claude는 그것도 함께 표시합니다.
- CPU와 같은 색상 기준을 씁니다. 하단에는 요금제(Max, Plus 등)와 데이터가 얼마나 최신인지가 표시됩니다.
- 오래된 데이터에는 항상 표시가 붙습니다. 로그인이 만료되면 "Expired"(만료됨), 요청이 실패하면 "Couldn't read"(읽기 실패), 한도 구간이 이미 초기화되었으면 "--"로 표시됩니다.

### 알림 배너

![네 가지 알림 배너](../images/banners.jpg)

어느 화면을 보고 있든 배너가 화면 전체를 덮고, 보드 뒷면의 RGB 조명이 같은 색으로 숨 쉬듯 깜빡입니다(조명은 끌 수 있습니다). 보드를 탭하거나 화면 전환 단축키를 누르면 배너가 닫힙니다.

| 배너 | 시점 | 색상 | 저절로 사라지는 때 |
|---|---|---|---|
| 집중 완료 | 집중 세션이 끝나고 휴식이 시작될 때. 휴식 카운트다운과 집중 중에 보류된 알림을 함께 보여 줍니다 | 초록 | 휴식이 끝날 때 |
| 휴식 종료 | 휴식이 끝날 때 | 빨강 | 다음 집중을 시작할 때 |
| 일어나기 | 컴퓨터를 실제로 50분 사용했을 때 | 주황 | 5분 동안 자리를 비웠을 때 |
| 물 마시기 | 컴퓨터를 60분 사용했을 때 | 파랑 | 사라지지 않음, 탭하여 닫기 |

- "컴퓨터 사용"은 키보드나 마우스 입력이 있는 상태를 말합니다. 유휴 시간과 화면이 잠기거나 잠자기 상태인 시간은 자리를 비운 시간으로 합산됩니다. 5분 동안 자리를 비우면 일어나기 타이머가 초기화되고, 30분이면 물 마시기 타이머가 초기화됩니다.
- 집중 중(일시 정지 포함)에는 배너가 뜨지 않습니다. 보류되었다가 "집중 완료" 배너에 합쳐서 표시됩니다.
- 한 번에 배너 하나만 표시되며, 표의 순서를 따릅니다.

### 화면 전환과 끄기

- 순서: 시스템 → 뽀모도로 → Claude → ChatGPT. 보드의 아무 곳이나 탭하거나 전역 단축키를 누릅니다. 배너가 떠 있는 동안에는 같은 동작이 배너를 닫습니다.
- 설정에서 끈 화면은 건너뜁니다. 오른쪽 위의 페이지 점이 현재 위치를 보여 줍니다.
- 디스플레이가 잠자기에 들어가거나, 화면이 잠기거나, 사용자를 전환하거나, Mac이 잠자기에 들어가면 화면과 조명이 곧바로 꺼지고, 이후 자동으로 돌아옵니다. Sysmon을 종료하거나 케이블을 뽑으면 약 10초 뒤에 화면이 꺼집니다.

## 메뉴 막대 앱

- 아이콘은 ESP32 모듈이며, 연결된 보드가 없으면 사선이 그어집니다.
- 메뉴에는 연결 상태, 지금 쓸 수 있는 뽀모도로 동작, 설정, Sysmon 정보, 종료가 있습니다.
- 설정에는 네 개의 탭이 있습니다.
  - **일반:** 화면 전환 단축키, RGB 조명, 앱 언어(시스템 설정 따르기 또는 10개 언어 중 하나), 로그인 시 실행.
  - **뽀모도로:** 뽀모도로 화면, 시작 / 일시 정지 단축키, 시간, 라운드당 횟수.
  - **알림:** 일어나기 알림과 물 마시기 알림, 그리고 각각의 간격.
  - **사용량:** Claude와 ChatGPT 사용량 화면과 그 상태, 그리고 데이터 출처.
- 전역 단축키는 Carbon 핫키를 사용하므로 손쉬운 사용 권한이 필요 없습니다. 사용자가 컴퓨터 앞에 있는지는 시스템 유휴 시간을 읽어 판단하며, 이 또한 권한이 필요 없습니다.
- 보드는 WCH(CH340) USB 벤더 ID로 찾으며, 다시 꽂으면 자동으로 재연결됩니다. 포트를 열거나 닫아도 보드가 리셋되지 않습니다.
- CPU 사용률은 0%에 가깝게 유지됩니다.

<p align="center">
  <img src="../images/macos-settings-general.png" width="49%" alt="Settings: General">
  <img src="../images/macos-settings-pomodoro.png" width="49%" alt="Settings: Pomodoro">
</p>
<p align="center">
  <img src="../images/macos-settings-reminders.png" width="49%" alt="Settings: Reminders">
  <img src="../images/macos-settings-usage.png" width="49%" alt="Settings: Usage">
</p>

### 사용량 데이터의 출처

Sysmon은 Mac에 이미 있는 로그인 정보를 읽기 전용으로 빌려 씁니다.

- **Claude:** 로그인 키체인에 있는 Claude Code 인증 정보(항목 `Claude Code-credentials`, `/usr/bin/security`로 읽으므로 권한 확인 창이 뜨지 않음)를 Anthropic의 사용량 엔드포인트로 보냅니다.
- **ChatGPT:** Codex의 `~/.codex/auth.json`을 ChatGPT의 사용량 엔드포인트로 보냅니다.

Sysmon은 이 로그인 정보를 갱신하지 않고 키체인이나 `auth.json`에 쓰지도 않으므로 사용자를 로그아웃시킬 수 없습니다. 대신 한동안 Claude Code나 Codex를 쓰지 않으면 로그인이 만료되어 화면에는 마지막 수치가 "만료됨"(Expired)으로 표시된 채 남습니다. 해결하려면 터미널에서 `claude`를 한 번 실행하거나 Codex를 한 번 여세요. 2분 안에 새 수치가 나타납니다. 사용량은 2분마다 가져오며, 화면이 꺼져 있는 동안에는 가져오지 않습니다.

두 엔드포인트 모두 문서화되어 있지 않아 언제든 바뀔 수 있습니다. 한쪽을 해석하지 못하면 해당 화면에만 "Couldn't read"(읽기 실패)가 표시됩니다.

## 요구 사항

| 항목 | 요구 사항 |
|---|---|
| 보드 | ESP32-2432S024R (ESP32-D0WD-V3, 플래시 4 MB, ST7789 240×320, CH340 시리얼) |
| Mac | macOS 14 이상 |
| 펌웨어 툴체인 | [PlatformIO](https://platformio.org/) |
| Mac 툴체인 | Xcode Command Line Tools (Swift 6) |

## 빠른 시작

```bash
git clone git@github.com:pokoblin/esp32-2432S024r-macos.git
cd esp32-2432S024r-macos
```

### 1. 펌웨어 굽기

```bash
cd sysmon/firmware
pio run -e esp32dev -t upload
```

`platformio.ini`는 `/dev/cu.usbserial-114110`을 사용하므로, 자신의 포트로 바꾸세요(`ls /dev/cu.usbserial-*`). 굽기 전에 Sysmon을 종료하세요. 그렇지 않으면 포트가 사용 중입니다.

> 이 보드는 USB 허브를 거치면 921600과 460800에서 굽기에 실패하므로 `upload_speed`는 115200으로 고정되어 있습니다.

### 2. 메뉴 막대 앱 설치

```bash
cd sysmon/macos
bash scripts/bundle.sh
open ~/Applications/Sysmon.app
```

`bundle.sh`는 릴리스 빌드를 만들고, `Sysmon.app`을 생성하고, ad hoc 서명을 한 뒤 `~/Applications`에 설치합니다. 원한다면 설정에서 "로그인 시 실행"을 켜세요.

## 개발

테스트 실행:

```bash
cd sysmon/firmware && pio test -e native
cd sysmon/macos && swift test
```

Sysmon 없이 보드 구동하기(pyserial 필요, PlatformIO의 Python에 이미 들어 있음):

```bash
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110                    # sys / pomo / cl / gpt, --page로 지정
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle            # 화면을 자동으로 순환
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page pomo --phase paused
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --banner done      # done / brk / sit / water
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
```

배너 제목에는 필요한 글자만 담은 아주 작은 폰트를 씁니다(펌웨어가 이미 플래시의 90% 넘게 사용합니다). `lib/sysmon_core/banner_titles.h`의 제목을 바꾼 뒤에는 이 폰트를 다시 생성해야 합니다. 폰트는 Source Han Sans CN Bold(SIL Open Font License 1.1)이며 로컬에 설치되어 있어야 합니다.

```bash
swift sysmon/tools/make_banner_font.swift ~/Library/Fonts/SourceHanSansCN-Bold.otf 24
```

README의 그림은 `docs/images/make_preview.py`와 `docs/images/make_screens.py`로 생성하며, 실행 명령은 각 스크립트 맨 위에 있습니다.

### 시리얼 프로토콜

115200 8N1, 일반 텍스트, 한 줄에 레코드 하나:

```
S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640
OFF
```

| 필드 | 의미 |
|---|---|
| `cpu` | CPU 사용률, 0–100 |
| `mem` | 메모리 압력 퍼센트, 0–100 |
| `lvl` | 메모리 압력 수준: 1 정상, 2 주의, 4 위험 |
| `rx` / `tx` | 다운로드 / 업로드 속도, 초당 바이트 |
| `OFF` | 다음 `S` 줄이 올 때까지 화면 끄기 |

펌웨어는 알 수 없는 줄과 필드를 무시합니다. 페이지, 사용량, 뽀모도로, 배너는 `P`, `U`, `T`, `B` 줄을 사용하고, 보드는 탭되면 `TAP`을 보냅니다. `usage_protocol.h`, `timer_protocol.h`, `Protocol.swift`의 헤더 주석을 참고하세요.

## 저장소 구조

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
    scripts/make_icon.sh     compiles the app icon from AppIcon.icon (Icon Composer)
  tools/fake_feed.py   fake data for the board, no Mac app needed
  tools/make_banner_font.swift  generates the banner title font
hw_probe/              hardware probe firmware: display driver, touch chip and pins
touch_diag/            raw XPT2046 touch diagnostics
touch_test/            touch calibration and drawing test; board.h is the verified display config
docs/images/           README pictures and their generators
docs/readme/           translated READMEs
```

## 하드웨어 메모

- 디스플레이 컨트롤러는 ILI9341이 아니라 **ST7789**입니다. `Panel_ILI9341`을 쓰면 화면이 전치되고 좌우가 뒤집혀 나옵니다.
- LovyanGFX 설정: `rgb_order=false`(true로 하면 빨강과 파랑이 바뀝니다), `invert=false`, 회전 0.
- 백라이트는 GPIO27, active high입니다. 디스플레이의 MISO는 연결되어 있지 않아 ID를 읽을 수 없습니다.
- 뒷면의 RGB LED는 common-anode, active low입니다. GPIO4 빨강, GPIO16 파랑, GPIO17 초록(파랑과 초록이 대부분의 CYD 자료와 반대입니다).
- CH340은 DTR/RTS로 EN과 GPIO0을 구동합니다. Sysmon은 포트를 연 직후 둘 다 해제하고 `HUPCL`을 꺼서, 포트를 열거나 닫아도 보드가 리셋되지 않게 합니다.
