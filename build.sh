#!/bin/bash
# Собирает FCS.app (universal: Apple Silicon + Intel) и устанавливает в /Applications.
# Нужны только Command Line Tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP="FCS.app"
rm -rf "$APP" .build_arm64 .build_x86
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Компиляция (arm64)…"
swiftc -parse-as-library -O -target arm64-apple-macos13.0 Sources/*.swift -o .build_arm64
echo "→ Компиляция (x86_64)…"
swiftc -parse-as-library -O -target x86_64-apple-macos13.0 Sources/*.swift -o .build_x86
lipo -create .build_arm64 .build_x86 -output "$APP/Contents/MacOS/FCS"
rm -f .build_arm64 .build_x86

cp Resources/icon-fcs.icns "$APP/Contents/Resources/icon-fcs.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FCS</string>
  <key>CFBundleDisplayName</key><string>FCS</string>
  <key>CFBundleIdentifier</key><string>com.local.fcs</string>
  <key>CFBundleExecutable</key><string>FCS</string>
  <key>CFBundleIconFile</key><string>icon-fcs</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRequiresAquaSystemAppearance</key><false/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "→ Установка в /Applications…"
pkill -x FCS 2>/dev/null || true
pkill -x FocusBlock 2>/dev/null || true
rm -rf "/Applications/FocusBlock.app" "/Applications/$APP"   # старая версия MVP
cp -R "$APP" /Applications/
touch "/Applications/$APP"
echo "Готово: /Applications/$APP"
open "/Applications/$APP"
