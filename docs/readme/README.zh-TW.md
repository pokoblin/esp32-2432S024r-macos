# Sysmon：ESP32-2432S024R 上的 Mac 系統狀態副螢幕

[English](../../README.md) | [简体中文](README.zh-CN.md) | **繁體中文** | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português (Brasil)](README.pt-BR.md) | [Русский](README.ru.md)

把一塊 ESP32-2432S024R（2.4 吋 ST7789 螢幕，俗稱「Cheap Yellow Display」）變成顯示器旁邊的小副螢幕。瞄一眼就能看到 CPU、記憶體壓力和網路速度，Claude 和 ChatGPT 訂閱額度還剩多少，還有一個番茄鐘，提醒你休息、起來走走、喝水。

選單列程式 **Sysmon** 每 2 秒擷取一次 Mac 的資料，透過 USB 序列埠傳給板子；板子負責畫圓環和曲線。不需要 Wi-Fi，也不會在 Mac 上開啟任何連接埠。

![顯示器旁的 Sysmon 副螢幕](../images/sysmon-preview.jpg)

<sub>示意圖依韌體的實際版面和配色繪製，資料為範例。</sub>

> **語言說明：** Mac 端程式支援 10 種語言。板子本身目前只顯示中文；本文的圖片呈現的是同一批畫面的英文版。

## 畫面

直式 240×320，深色背景。共有四個畫面：系統狀態、番茄、Claude 用量和 ChatGPT 用量。提醒橫幅可以蓋在任何一個畫面上。

![四個畫面](../images/screens.jpg)

### 系統狀態畫面

- **上半部：** CPU 和記憶體壓力兩個圓環。CPU 到 50% 變黃，到 80% 變紅。記憶體圓環跟隨 macOS 的記憶體壓力等級（正常 / 警告 / 嚴重），和「活動監視器」一致。
- **下半部：** 目前的下載和上傳速度，以及最近 5 分鐘的雙色曲線。曲線依這 5 分鐘內的峰值縮放。

### 番茄畫面

- 大圓環表示目前這一段還剩多少，並顯示剩餘時間、階段名稱和結束時刻。專注為番茄紅，短休為綠色，長休為藍色；暫停或尚未開始時為灰色。
- 下方：這一輪的進度點（預設每輪 4 個專注），例如「第 2 個 · 再 2 個後長休」，以及今日統計，例如「今天 5 個 · 2小時05分」。
- 預設值：專注 25 分鐘，短休 5 分鐘，每 4 個專注之後長休 15 分鐘。皆可調整，更改從下一段開始生效。
- 只有專注需要手動開始：專注結束後直接進入休息，休息結束後則會停下來等你。
- 開始、暫停、繼續可用一個全域快速鍵，或從選單操作；選單裡還有「跳過」和「重設輪次」。在專注中跳過等於放棄這個番茄，不會列入統計。
- 計時依真實時間進行，離開電腦、鎖定螢幕或 Mac 睡眠期間都照常計時。今日統計過了午夜會歸零，重新啟動後仍會保留。
- 專注期間，其他畫面的最上方會有一條 3 px 的番茄紅進度線（暫停時變灰）。

### Claude 和 ChatGPT 用量畫面

- 大圓環表示 5 小時額度，並顯示距離重置的時間；每週額度以進度條表示（「本週 · 週四 14:00 重置」）。當 API 有回報時，Claude 畫面還會顯示依模型分別計算的每週額度。
- 顏色門檻與 CPU 相同。底部顯示方案（Max、Plus……）和資料的新鮮度。
- 過時的資料一定會標示出來：登入失效時顯示「已過期」，請求失敗時顯示「讀取失敗」，某個額度時段已經重置時顯示「--」。

### 提醒橫幅

![四種提醒橫幅](../images/banners.jpg)

不論停在哪個畫面，橫幅都會占滿整個螢幕，板子背面的 RGB 燈也會用同樣的顏色呼吸（燈可以關閉）。點一下板子，或按切換畫面的快速鍵就能關掉橫幅。

| 橫幅 | 何時出現 | 顏色 | 會自動消失嗎 |
|---|---|---|---|
| 專注完成 | 專注結束、休息開始；顯示休息倒數，以及專注期間被暫緩的提醒 | 綠 | 休息結束時 |
| 休息結束 | 休息結束 | 紅 | 開始下一個專注時 |
| 該起來走走了 | 實際使用電腦滿 50 分鐘 | 橘 | 離開電腦滿 5 分鐘後 |
| 該喝水了 | 使用電腦滿 60 分鐘 | 藍 | 不會，需點一下才會關閉 |

- 「使用電腦」指有鍵盤或滑鼠操作。閒置、鎖定螢幕或睡眠的時間都算離開：離開 5 分鐘，久坐計時重新開始；離開 30 分鐘，喝水計時重新開始。
- 專注期間（包括暫停）不會出現橫幅：這些提醒會被暫緩，並合併到「專注完成」橫幅裡。
- 一次只顯示一個橫幅，順序與表格中的順序一致。

### 切換畫面與熄屏

- 順序：系統狀態 → 番茄 → Claude → ChatGPT。點一下板子上的任何位置，或按全域快速鍵。顯示橫幅時，同樣的操作會關閉橫幅，而不是切換畫面。
- 在設定中關閉的畫面會被略過。右上角的頁碼小點會顯示目前在哪一個畫面。
- 顯示器睡眠、鎖定螢幕、切換使用者或 Mac 睡眠時，螢幕和燈會立即熄滅，之後自動恢復。Sysmon 結束或拔掉線後約 10 秒，螢幕會熄滅。

## 選單列程式

- 圖示是一塊 ESP32 模組；沒有連接板子時會加上一條斜線。
- 選單裡有連線狀態、目前可用的番茄操作、設定、關於和結束。
- 設定分為四個標籤頁：
  - **一般：** 切換副螢幕的快速鍵、RGB 燈、App 語言（跟隨系統，或 10 種語言之一）和登入時啟動。
  - **番茄鐘：** 番茄畫面、開始 / 暫停快速鍵、各段時長和每輪個數。
  - **健康提醒：** 久坐提醒和喝水提醒，以及它們的間隔。
  - **用量：** Claude 和 ChatGPT 用量畫面及其狀態，以及資料的來源。
- 全域快速鍵使用 Carbon 熱鍵，因此不需要輔助使用權限。判斷你是否在電腦前讀取的是系統閒置時間，同樣不需要權限。
- 它依 WCH（CH340）的 USB 供應商 ID 尋找板子，重新插拔後會自動重新連線。開啟或關閉序列埠都不會讓板子重設。
- CPU 使用率接近 0%。

<!-- 選單和設定視窗的截圖放在這裡，例如 ../images/macos-menu.png 和 ../images/macos-settings.png -->

### 用量資料從哪裡來

Sysmon 借用 Mac 上既有的登入，唯讀不寫：

- **Claude：** 登入鑰匙圈中 Claude Code 的憑證（項目 `Claude Code-credentials`，透過 `/usr/bin/security` 讀取，因此不會跳出權限提示），傳給 Anthropic 的用量端點。
- **ChatGPT：** Codex 的 `~/.codex/auth.json`，傳給 ChatGPT 的用量端點。

Sysmon 從不續期這些登入，也從不寫入鑰匙圈或 `auth.json`，所以不會讓你被登出。代價是：一段時間沒使用 Claude Code 或 Codex，登入就會過期，畫面會停在最後一次的數字並標示為「已過期」。恢復的方法是在終端機裡執行一次 `claude`，或開啟一次 Codex；2 分鐘內就會出現新的數字。用量每 2 分鐘擷取一次，熄屏期間不擷取。

這兩個端點都沒有公開文件，隨時可能變動。如果其中一個無法解析，只有對應的那個畫面會顯示「讀取失敗」。

## 系統需求

| 項目 | 需求 |
|---|---|
| 板子 | ESP32-2432S024R（ESP32-D0WD-V3，4 MB flash，ST7789 240×320，CH340 序列埠） |
| Mac | macOS 14 或更新版本 |
| 韌體工具鏈 | [PlatformIO](https://platformio.org/) |
| Mac 工具鏈 | Xcode Command Line Tools（Swift 6） |

## 快速開始

```bash
git clone git@github.com:pokoblin/esp32-2432S024r-macos.git
cd esp32-2432S024r-macos
```

### 1. 燒錄韌體

```bash
cd sysmon/firmware
pio run -e esp32dev -t upload
```

`platformio.ini` 使用的是 `/dev/cu.usbserial-114110`，請改成你自己的連接埠（`ls /dev/cu.usbserial-*`）。燒錄前請先結束 Sysmon，否則連接埠會被占用。

> 透過 USB 集線器時，這塊板子以 921600 和 460800 都會燒錄失敗，因此 `upload_speed` 固定為 115200。

### 2. 安裝選單列程式

```bash
cd sysmon/macos
bash scripts/bundle.sh
open ~/Applications/Sysmon.app
```

`bundle.sh` 會建置 release 版本、產生 `Sysmon.app`、做 ad hoc 簽署，並安裝到 `~/Applications`。需要的話，可在設定中開啟「登入時啟動」。

## 開發

執行測試：

```bash
cd sysmon/firmware && pio test -e native
cd sysmon/macos && swift test
```

不透過 Sysmon 直接驅動板子（需要 pyserial；PlatformIO 內建的 Python 已經有）：

```bash
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110                    # 搭配 --page 選 sys / pomo / cl / gpt
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle            # 自動輪換畫面
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page pomo --phase paused
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --banner done      # done / brk / sit / water
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
```

橫幅標題使用一個很小的字型，只包含它們需要的字元（韌體已經用掉 90% 以上的 flash）。修改 `lib/sysmon_core/banner_titles.h` 裡的標題之後，需要重新產生字型；字型是思源黑體 CN Bold（SIL Open Font License 1.1），必須先安裝在本機：

```bash
swift sysmon/tools/make_banner_font.swift ~/Library/Fonts/SourceHanSansCN-Bold.otf 24
```

README 裡的圖片由 `docs/images/make_preview.py` 和 `docs/images/make_screens.py` 產生，指令寫在各腳本的開頭。

### 序列埠協定

115200 8N1，純文字，每行一筆記錄：

```
S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640
OFF
```

| 欄位 | 意義 |
|---|---|
| `cpu` | CPU 使用率，0–100 |
| `mem` | 記憶體壓力百分比，0–100 |
| `lvl` | 記憶體壓力等級：1 正常，2 警告，4 嚴重 |
| `rx` / `tx` | 下載 / 上傳速度，每秒位元組數 |
| `OFF` | 熄屏，直到下一行 `S` |

韌體會忽略不認識的行和欄位。頁面、用量、番茄和橫幅使用的是 `P`、`U`、`T`、`B` 行，板子被點一下時會送出 `TAP`：詳見 `usage_protocol.h`、`timer_protocol.h` 和 `Protocol.swift` 的標頭註解。

## 專案結構

```
sysmon/
  firmware/            ESP32 韌體（PlatformIO + Arduino + LovyanGFX）
    lib/sysmon_core/   純邏輯：協定解析、熄屏狀態、曲線歷史、文案、點按防彈跳、顏色、呼吸曲線
    src/               螢幕設定、繪製、RGB 燈、產生的橫幅字型、主迴圈
    test/              在電腦上執行的單元測試
  macos/               選單列程式（SwiftPM）
    Sources/SysmonCore/  CPU/記憶體/網路取樣、序列埠、裝置探索、用量憑證與解析、
                         頁面順序、番茄與提醒規則、在地化
    Sources/Sysmon/      SwiftUI 選單列介面、設定、關於、全域快速鍵
    scripts/bundle.sh    建置並安裝 .app
  tools/fake_feed.py   對板子送出模擬資料，不需要 Mac 端程式
  tools/make_banner_font.swift  產生橫幅標題字型
hw_probe/              硬體探測韌體：螢幕驅動程式、觸控晶片和腳位
touch_diag/            XPT2046 觸控原始資料診斷
touch_test/            觸控校正和繪圖測試；board.h 是驗證過的螢幕設定
.superpowers/          設計階段的介面草圖
docs/images/           README 圖片及其產生腳本
docs/readme/           翻譯版 README
```

## 硬體筆記

- 螢幕控制器是 **ST7789**，不是 ILI9341。使用 `Panel_ILI9341` 的話，畫面會轉置並鏡像。
- LovyanGFX 設定：`rgb_order=false`（設為 true 會讓紅藍互換），`invert=false`，旋轉 0。
- 背光接在 GPIO27，高電位有效。螢幕的 MISO 沒有接出來，所以讀不到它的 ID。
- 背面的 RGB LED 是共陽極、低電位點亮：GPIO4 紅，GPIO16 藍，GPIO17 綠（藍和綠與大多數 CYD 資料裡寫的正好相反）。
- CH340 透過 DTR/RTS 控制 EN 和 GPIO0。Sysmon 開啟序列埠後會立刻把這兩個訊號都清除，並關閉 `HUPCL`，因此開啟或關閉序列埠都不會讓板子重設。
