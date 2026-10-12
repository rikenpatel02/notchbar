#!/usr/bin/env bash
# Builds NotchBar.app into ./build.
#   --run        launch the local build
#   --install    copy to /Applications (stable path for Claude Code hooks + login item) and launch
#   --universal  build for Apple Silicon and Intel (used for releases)
#
# Environment:
#   VERSION        marketing version, default 0.1.0
#   BUILD_NUMBER   CFBundleVersion, default 1
#   SIGN_IDENTITY  "Developer ID Application: ..." to sign with hardened runtime; ad-hoc when unset
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/NotchBar.app"
UNIVERSAL=false
ACTION=""
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=true ;;
    --run|--install) ACTION="$arg" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if $UNIVERSAL; then
  for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx13.0"
  done
  lipo -create -output "$APP/Contents/MacOS/NotchBar" \
    .build/arm64-apple-macosx/release/NotchBar \
    .build/x86_64-apple-macosx/release/NotchBar
else
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/NotchBar" "$APP/Contents/MacOS/NotchBar"
fi

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchBar</string>
  <key>CFBundleDisplayName</key><string>NotchBar</string>
  <key>CFBundleIdentifier</key><string>com.rikenpatel.notchbar</string>
  <key>CFBundleExecutable</key><string>NotchBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSAppleEventsUsageDescription</key><string>NotchBar brings a Claude Code session's terminal tab to the front, and skips banners for the tab you are already looking at.</string>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements NotchBar.entitlements --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/NotchBar"))"

case "$ACTION" in
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
