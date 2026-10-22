#!/bin/bash
# 编译 App 图标：AppIcon.icon 是 Icon Composer 格式（macOS 26 起苹果的标准做法，分层 SVG + icon.json），
# 系统据此加上 Liquid Glass 材质、高光和阴影，并跟着切换深色、着色、透明外观。
# 改图标：用 Xcode 自带的 Icon Composer 打开 AppIcon.icon，或直接改 AppIcon.icon/Assets 里的 SVG，然后重跑本脚本。
# 输出 Resources/Assets.car（新系统用）和 Resources/AppIcon.icns（旧系统用），都提交进仓库，
# 所以只装了命令行工具、没有完整 Xcode 也能用 bundle.sh 打包。另外导出 README 用的 docs/images/icon.png。
# 用法：cd sysmon/macos && bash scripts/make_icon.sh（需要 Xcode 26 或更新）
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Resources
xcrun actool AppIcon.icon --compile Resources --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$(mktemp -t sysmon-icon)" --errors --warnings >/dev/null

"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" AppIcon.icon \
    --export-image --output-file ../../docs/images/icon.png --platform macOS --rendition Default \
    --width 256 --height 256 --scale 1 >/dev/null 2>&1 \
  || "/Applications/Icon Composer.app/Contents/Executables/ictool" AppIcon.icon \
    --export-image --output-file ../../docs/images/icon.png --platform macOS --rendition Default \
    --width 256 --height 256 --scale 1 >/dev/null
# README 里的图标压一下（有 pngquant 才压）
command -v pngquant >/dev/null && pngquant --quality=80-95 --strip --force --output ../../docs/images/icon.png ../../docs/images/icon.png
ls -la Resources ../../docs/images/icon.png
