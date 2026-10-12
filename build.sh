#!/usr/bin/env bash
# Builds NotchBar.app into ./build.
#   --run      launch the local build
#   --install  copy to /Applications (stable path for Claude Code hooks + login item) and launch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchBar"
APP="build/NotchBar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NotchBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchBar</string>
  <key>CFBundleIdentifier</key><string>com.rikenpatel.notchbar</string>
  <key>CFBundleExecutable</key><string>NotchBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>NotchBar brings a Claude Code session's terminal tab to the front, and skips banners for the tab you are already looking at.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

case "${1:-}" in
  --run)
    pkill -x NotchBar || true
    open "$APP"
    ;;
  --install)
    pkill -x NotchBar || true
    rm -rf /Applications/NotchBar.app
    cp -R "$APP" /Applications/NotchBar.app
    open /Applications/NotchBar.app
    echo "Installed /Applications/NotchBar.app"
    ;;
esac
