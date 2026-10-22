<p align="center"><img src="../images/icon.png" width="128" alt="Sysmon icon"></p>

# Sysmon：ESP32-2432S024R 上的 Mac 系统状态副屏

[English](../../README.md) | **简体中文** | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português (Brasil)](README.pt-BR.md) | [Русский](README.ru.md)

把一块 ESP32-2432S024R（2.4 寸 ST7789 屏，俗称“Cheap Yellow Display”）变成显示器旁边的小副屏。扫一眼就能看到 CPU、内存压力和网速，Claude 和 ChatGPT 订阅额度还剩多少，还有一个番茄钟，提醒你休息、起来走走、喝水。

菜单栏程序 **Sysmon** 每 2 秒采集一次 Mac 的数据，通过 USB 串口发给板子；板子负责画圆环和曲线。不需要 Wi-Fi，也不在 Mac 上开任何端口。

![显示器旁的 Sysmon 副屏](../images/sysmon-preview.jpg)

<sub>示意图按固件的实际布局和配色绘制，数据为示例。</sub>

> **语言说明：** Mac 端程序支持 10 种语言。板子本身目前只显示中文；本文的图片展示的是同一批画面的英文版。

## 屏幕

竖屏 240×320，深色背景。一共四屏：系统状态、番茄、Claude 用量和 ChatGPT 用量。提醒横幅可以盖在任意一屏上面。

![四个屏幕](../images/screens.jpg)

### 系统状态屏

- **上半屏：** CPU 和内存压力两个圆环。CPU 到 50% 变黄，到 80% 变红。内存圆环跟随 macOS 的内存压力等级（正常 / 警告 / 严重），和“活动监视器”一致。
- **下半屏：** 当前的下载和上传速度，以及最近 5 分钟的两色曲线。曲线按这 5 分钟内的峰值缩放。

### 番茄屏

- 大圆环表示当前这一段还剩多少，并显示剩余时间、阶段名和结束时刻。专注为番茄红，短休为绿色，长休为蓝色；暂停或还没开始时为灰色。
- 下方：这一轮的进度点（默认每轮 4 个专注），例如“第 2 个 · 再 2 个后长休”，以及今日统计，例如“今天 5 个 · 2小时05分”。
- 默认值：专注 25 分钟，短休 5 分钟，每 4 个专注之后长休 15 分钟。都可以调整，改动从下一段开始生效。
- 只有专注需要手动开始：专注走完直接进入休息，休息走完则停下来等你。
- 开始、暂停、继续用一个全局快捷键，或者在菜单里操作；菜单里还有“跳过”和“重置轮次”。专注中跳过等于放弃这个番茄，不计入统计。
- 计时按真实时间走，离开电脑、锁屏或 Mac 睡眠期间都照常走。今日统计过了零点清零，重启后仍然保留。
- 专注期间，其他屏的最顶上会有一条 3 px 的番茄红进度线（暂停时变灰）。

### Claude 和 ChatGPT 用量屏

- 大圆环表示 5 小时额度，并显示距离重置的时间；每周额度用进度条表示（“本周 · 周四 14:00 重置”）。接口返回时，Claude 屏还会显示按模型单独计算的每周额度。
- 颜色阈值和 CPU 相同。底栏显示套餐（Max、Plus……）和数据的新鲜度。
- 过时的数据一定会标出来：登录失效时显示“已过期”，请求失败时显示“读取失败”，某个额度窗口已经重置时显示“--”。

### 提醒横幅

![四种提醒横幅](../images/banners.jpg)

不管停在哪一屏，横幅都会占满整个屏幕，板子背面的 RGB 灯也会用同样的颜色呼吸（灯可以关掉）。点一下板子，或按切屏快捷键就能关掉横幅。

| 横幅 | 什么时候出现 | 颜色 | 会自己消失吗 |
|---|---|---|---|
| 专注完成 | 专注结束、休息开始；显示休息倒计时，以及专注期间被压住的提醒 | 绿 | 休息结束时 |
| 休息结束 | 休息结束 | 红 | 开始下一个专注时 |
| 该起来走走了 | 实际用电脑满 50 分钟 | 橙 | 离开电脑满 5 分钟后 |
| 该喝水了 | 用电脑满 60 分钟 | 蓝 | 不会，点一下才关掉 |

- “用电脑”指有键盘或鼠标活动。闲置、锁屏或睡眠的时间都算离开：离开 5 分钟，久坐计时重新开始；离开 30 分钟，喝水计时重新开始。
- 专注期间（包括暂停）不出横幅：这些提醒会被压住，并进“专注完成”横幅里。
- 一次只显示一个横幅，顺序和表格里的顺序一致。

### 切换屏幕和熄屏

- 顺序：系统状态 → 番茄 → Claude → ChatGPT。点一下板子上的任意位置，或按全局快捷键。有横幅时，同样的操作是关掉横幅，不切屏。
- 在设置里关掉的屏会被跳过。右上角的页码小点显示当前在哪一屏。
- 显示器睡眠、锁屏、切换用户或 Mac 睡眠时，屏幕和灯立刻熄灭，之后自动恢复。Sysmon 退出或拔掉线后约 10 秒，屏幕熄灭。

## 菜单栏程序

- 图标是一块 ESP32 模块；没连上板子时带一条斜杠。
- 菜单里有连接状态、当前能用的番茄操作、设置、关于和退出。
- 设置分四个标签页：
  - **通用：** 切换副屏的快捷键、RGB 灯、App 语言（跟随系统，或 10 种语言之一）和开机时启动。
  - **番茄钟：** 番茄屏、开始 / 暂停快捷键、各段时长和每轮个数。
  - **健康提醒：** 久坐提醒和喝水提醒，以及它们的间隔。
  - **用量：** Claude 和 ChatGPT 用量屏及其状态，以及数据的来源。
- 全局快捷键用的是 Carbon 热键，所以不需要辅助功能权限。判断你是否在电脑前读的是系统闲置时间，同样不需要权限。
- 它按 WCH（CH340）的 USB 厂商 ID 找板子，重新插拔后自动重连。打开或关闭串口都不会让板子复位。
- CPU 占用接近 0%。

<p align="center">
  <img src="../images/macos-settings-general.png" width="49%" alt="Settings: General">
  <img src="../images/macos-settings-pomodoro.png" width="49%" alt="Settings: Pomodoro">
</p>
<p align="center">
  <img src="../images/macos-settings-reminders.png" width="49%" alt="Settings: Reminders">
  <img src="../images/macos-settings-usage.png" width="49%" alt="Settings: Usage">
</p>

### 用量数据从哪来

Sysmon 借用 Mac 上已有的登录，只读不写：

- **Claude：** 登录钥匙串里 Claude Code 的凭据（条目 `Claude Code-credentials`，通过 `/usr/bin/security` 读取，所以不会弹出权限提示），发给 Anthropic 的用量接口。
- **ChatGPT：** Codex 的 `~/.codex/auth.json`，发给 ChatGPT 的用量接口。

Sysmon 从不续期这些登录，也从不写钥匙串或 `auth.json`，所以不会把你登出。代价是：一段时间不用 Claude Code 或 Codex，登录就会过期，屏幕会停在最后一次的数字上并标成“已过期”。恢复的办法是在终端里运行一次 `claude`，或者打开一次 Codex；2 分钟内就会出现新数字。用量每 2 分钟拉取一次，熄屏期间不拉取。

这两个接口都没有公开文档，随时可能变化。如果其中一个解析不了，只有对应的那一屏显示“读取失败”。

## 环境要求

| 项目 | 要求 |
|---|---|
| 板子 | ESP32-2432S024R（ESP32-D0WD-V3，4 MB flash，ST7789 240×320，CH340 串口） |
| Mac | macOS 14 或更新版本 |
| 固件工具链 | [PlatformIO](https://platformio.org/) |
| Mac 工具链 | Xcode Command Line Tools（Swift 6） |

## 快速开始

```bash
git clone git@github.com:pokoblin/esp32-2432S024r-macos.git
cd esp32-2432S024r-macos
```

### 1. 烧录固件

```bash
cd sysmon/firmware
pio run -e esp32dev -t upload
```

`platformio.ini` 里用的是 `/dev/cu.usbserial-114110`，请改成你自己的端口（`ls /dev/cu.usbserial-*`）。烧录前先退出 Sysmon，否则端口会被占用。

> 经过 USB 集线器时，这块板子用 921600 和 460800 都烧录失败，所以 `upload_speed` 固定为 115200。

### 2. 安装菜单栏程序

```bash
cd sysmon/macos
bash scripts/bundle.sh
open ~/Applications/Sysmon.app
```

`bundle.sh` 会构建 release 版本，生成 `Sysmon.app`，做 ad hoc 签名，并安装到 `~/Applications`。需要的话，在设置里打开“开机时启动”。

## 开发

运行测试：

```bash
cd sysmon/firmware && pio test -e native
cd sysmon/macos && swift test
```

不用 Sysmon 直接驱动板子（需要 pyserial；PlatformIO 自带的 Python 里已经有）：

```bash
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110                    # 配合 --page 选 sys / pomo / cl / gpt
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle            # 自动轮换屏幕
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page pomo --phase paused
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --banner done      # done / brk / sit / water
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
```

横幅标题用的是一个很小的字体，只包含它们需要的字（固件已经用掉了 90% 以上的 flash）。修改 `lib/sysmon_core/banner_titles.h` 里的标题之后，需要重新生成字体；字体是思源黑体 CN Bold（SIL Open Font License 1.1），需要先安装到本机：

```bash
swift sysmon/tools/make_banner_font.swift ~/Library/Fonts/SourceHanSansCN-Bold.otf 24
```

README 里的图片由 `docs/images/make_preview.py` 和 `docs/images/make_screens.py` 生成，命令写在各脚本的开头。

### 串口协议

115200 8N1，纯文本，每行一条记录：

```
S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640
OFF
```

| 字段 | 含义 |
|---|---|
| `cpu` | CPU 使用率，0–100 |
| `mem` | 内存压力百分比，0–100 |
| `lvl` | 内存压力等级：1 正常，2 警告，4 严重 |
| `rx` / `tx` | 下载 / 上传速度，字节每秒 |
| `OFF` | 熄屏，直到下一条 `S` 行 |

固件会忽略不认识的行和字段。页面、用量、番茄和横幅用的是 `P`、`U`、`T`、`B` 行，板子被点一下时会发 `TAP`：详见 `usage_protocol.h`、`timer_protocol.h` 和 `Protocol.swift` 的头部注释。

## 仓库结构

```
sysmon/
  firmware/            ESP32 固件（PlatformIO + Arduino + LovyanGFX）
    lib/sysmon_core/   纯逻辑：协议解析、熄屏状态、曲线历史、文案、点按防抖、颜色、呼吸曲线
    src/               屏幕配置、绘制、RGB 灯、生成的横幅字体、主循环
    test/              在电脑上运行的单元测试
  macos/               菜单栏程序（SwiftPM）
    Sources/SysmonCore/  CPU/内存/网络采样、串口、设备发现、用量凭据与解析、
                         页面顺序、番茄与提醒规则、本地化
    Sources/Sysmon/      SwiftUI 菜单栏界面、设置、关于、全局快捷键
    scripts/bundle.sh    构建并安装 .app
    scripts/make_icon.sh     从 AppIcon.icon（Icon Composer 格式）编译 App 图标
  tools/fake_feed.py   给板子发模拟数据，不需要 Mac 端程序
  tools/make_banner_font.swift  生成横幅标题字体
hw_probe/              硬件探测固件：屏幕驱动、触摸芯片和引脚
touch_diag/            XPT2046 触摸原始数据诊断
touch_test/            触摸校准和画线测试；board.h 是验证过的屏幕配置
.superpowers/          设计阶段的界面草图
docs/images/           README 图片及其生成脚本
docs/readme/           翻译版 README
```

## 硬件笔记

- 屏幕控制器是 **ST7789**，不是 ILI9341。用 `Panel_ILI9341` 的话，画面会转置并镜像。
- LovyanGFX 设置：`rgb_order=false`（设成 true 会红蓝互换），`invert=false`，旋转 0。
- 背光接在 GPIO27，高电平有效。屏幕的 MISO 没有接出来，所以读不到它的 ID。
- 背面的 RGB LED 是共阳极、低电平点亮：GPIO4 红，GPIO16 蓝，GPIO17 绿（蓝和绿与大多数 CYD 资料里写的正好相反）。
- CH340 通过 DTR/RTS 控制 EN 和 GPIO0。Sysmon 打开串口后立刻把这两个信号都清掉，并关闭 `HUPCL`，所以打开或关闭串口都不会让板子复位。
