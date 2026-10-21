# ESP32 Mac 系统状态副屏

把一块 ESP32-2432S024R（2.4 寸 ST7789 屏，俗称 CYD）变成 Mac 的系统状态副屏：贴在显示器旁边，扫一眼就能看到 CPU、内存压力和网速。

Mac 上的菜单栏程序 **Sysmon** 每 2 秒采集一次数据，通过 USB 串口发给板子；板子负责画圆环和曲线。不需要 WiFi，也不在 Mac 上开任何端口。

## 屏幕上有什么

竖屏 240×320，深色背景：

- **上半屏**：CPU 和内存压力两个圆环。
  - CPU 圆环按占用率变色：低于 50% 绿色，50–79% 黄色，80% 及以上红色。
  - 内存圆环的颜色跟随系统的内存压力等级（正常 / 警告 / 严重），和“活动监视器”一致；圆环长度和中间的数字是压力百分比。
- **下半屏**：下载和上传的当前速度，以及最近 5 分钟的两色曲线。
  - 速度默认用 MB/s，满 1000 MB/s 改用 GB/s，保留约 3 位有效数字。
  - 曲线高度按 5 分钟内的峰值自动缩放，右上角标出峰值。

**什么时候熄屏**

- 显示器睡眠、锁屏、切换用户或 Mac 睡眠时，副屏立即熄灭，恢复后自动亮起。
- 退出 Sysmon 或拔掉线后，约 10 秒熄屏。
- 数据中断超过 5 分钟，再次亮屏时曲线从头开始。

## 菜单栏程序 Sysmon

- 图标是一块 ESP32 模组；未连接板子时图标上多一道斜杠。
- 菜单里显示连接状态、当前数值摘要、“开机时启动”开关和“退出”。
- 网速只统计有线和 WiFi（`en*` 网卡），开全局代理或 VPN 时不会重复计算。
- 自动按 WCH（CH340）的 USB 厂商 ID 找板子，拔插后自动重连；打开和关闭串口都不会让板子复位。
- 平时 CPU 占用接近 0%。

## 需要什么

| 项目 | 要求 |
|---|---|
| 开发板 | ESP32-2432S024R（ESP32-D0WD-V3，4MB Flash，ST7789 240×320，CH340 串口） |
| Mac | macOS 14 或更新版本 |
| 固件工具链 | [PlatformIO](https://platformio.org/) |
| Mac 端工具链 | Xcode 命令行工具（Swift 6） |

## 快速开始

### 1. 烧录固件

```bash
cd sysmon/firmware
pio run -e esp32dev -t upload
```

`platformio.ini` 里的串口写的是 `/dev/cu.usbserial-114110`，换了 USB 口要改成你自己的（用 `ls /dev/cu.usbserial-*` 查看）。烧录前先退出 Sysmon，否则串口被占用会失败。

> 这块板子经过 USB Hub 时，921600 和 460800 的烧录速率都会出错，所以 `upload_speed` 固定为 115200。

### 2. 安装菜单栏程序

```bash
cd sysmon/macos
bash scripts/bundle.sh
open ~/Applications/Sysmon.app
```

`bundle.sh` 会编译 release 版本、生成 `Sysmon.app`、做 ad-hoc 签名，并安装到 `~/Applications`。需要开机自动运行的话，在菜单里打开“开机时启动”。

## 目录结构

```
sysmon/
  firmware/            ESP32 固件（PlatformIO + Arduino + LovyanGFX）
    lib/sysmon_core/   纯逻辑：协议解析、熄屏状态、曲线历史、网速格式化、配色
    src/               屏幕配置、画面绘制、主循环
    test/              在电脑上跑的单元测试
  macos/               Mac 菜单栏程序（SwiftPM）
    Sources/SysmonCore/  采集 CPU/内存/网速、串口、设备识别
    Sources/Sysmon/      SwiftUI 菜单栏界面
    scripts/bundle.sh    打包并安装 .app
  tools/fake_feed.py   给板子发模拟数据，不用 Mac 端程序也能调屏幕
hw_probe/              硬件探测固件：识别屏幕驱动、触摸芯片和引脚
touch_diag/            XPT2046 触摸原始信号诊断
touch_test/            触摸校准与画点测试；board.h 是验证过的屏幕配置
.superpowers/          设计阶段的界面效果图
```

## 开发

运行测试：

```bash
cd sysmon/firmware && pio test -e native
cd sysmon/macos && swift test
```

不开 Sysmon，直接给板子发模拟数据。脚本需要 pyserial（`pip install pyserial`，PlatformIO 自带的 Python 环境里已经有了）：

```bash
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
```

### 串口协议

115200 8N1，纯文本，一行一条：

```
S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640
OFF
```

| 字段 | 含义 |
|---|---|
| `cpu` | CPU 占用，0–100 |
| `mem` | 内存压力百分比，0–100 |
| `lvl` | 内存压力等级：1 正常，2 警告，4 严重 |
| `rx` / `tx` | 下载 / 上传速度，字节每秒 |
| `OFF` | 立即熄屏，收到下一条 `S` 行时恢复 |

固件会忽略不认识的行和字段，以后加指标时可以直接加字段。

## 硬件备忘

- 屏幕驱动是 **ST7789**，不是 ILI9341。用 `Panel_ILI9341` 驱动时画面会转置加镜像。
- LovyanGFX 配置：`rgb_order=false`（设为 true 会红蓝互换），`invert=false`，rotation 0。
- 背光接 GPIO27，高电平点亮；屏幕的 MISO 没接，读不出芯片 ID。
- CH340 通过 DTR/RTS 控制 EN 和 GPIO0。Sysmon 打开串口后会立即同时清掉 DTR 和 RTS，并关闭 `HUPCL`，所以打开、关闭串口都不会复位板子。
