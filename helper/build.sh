#!/bin/bash
# 编译浮窗小程序，打包成 helper/.build/Zh2En.app（只编译，不安装；安装由 ../install.sh 负责）
# 编译缓存全放在 helper/.build/ 里，不往系统共用缓存里写东西。
#   BUNDLE_ID=com.example.zh2en bash build.sh   可以换 bundle id
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/.build"
APP="$BUILD/Zh2En.app"
BUNDLE_ID="${BUNDLE_ID:-io.github.zh2en}"

mkdir -p "$BUILD/module-cache"
swiftc -O -module-name Zh2En \
  -module-cache-path "$BUILD/module-cache" \
  -o "$BUILD/Zh2En" "$HERE"/Sources/*.swift

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD/Zh2En" "$APP/Contents/MacOS/Zh2En"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>Zh2En</string>
  <key>CFBundleDisplayName</key><string>边打边学</string>
  <key>CFBundleExecutable</key><string>Zh2En</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "已编译：$APP"
