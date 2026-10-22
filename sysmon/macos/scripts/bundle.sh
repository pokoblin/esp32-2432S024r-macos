#!/bin/bash
# 构建 Sysmon.app（菜单栏程序，不进 Dock），ad-hoc 签名后安装到 ~/Applications。
# 用法：cd sysmon/macos && bash scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Sysmon.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Sysmon" "$APP/Contents/MacOS/Sysmon"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.pokoblin.sysmon</string>
  <key>CFBundleName</key><string>Sysmon</string>
  <key>CFBundleExecutable</key><string>Sysmon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

mkdir -p ~/Applications
pkill -x Sysmon 2>/dev/null || true
rm -rf ~/Applications/Sysmon.app
ditto "$APP" ~/Applications/Sysmon.app
echo "installed ~/Applications/Sysmon.app"
