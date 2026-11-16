#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="ServiceWatch"
BUNDLE_ID="com.sevacenix.ServiceWatch.Open.Dev"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_BUNDLE="$HOME/Library/Caches/$BUNDLE_ID/$APP_NAME.app"
if /usr/bin/pgrep -f "^$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null; then
  echo "Quit the running development app before rebuilding." >&2
  exit 1
fi
./script/build_icon.sh
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp -X Sources/ServiceWatch/Resources/English.json "$APP_BUNDLE/Contents/Resources/English.json"
cp -X "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ -f Assets/AppIcon/AppIcon.icns ]]; then
  cp -X Assets/AppIcon/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>续期开发版</string>
<key>ServiceWatchIsolatedData</key><true/>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
codesign --force --sign - "$APP_BUNDLE" >/dev/null
open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
  sleep 1
}
case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; pgrep -f "^$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null; codesign --verify --deep --strict "$APP_BUNDLE" ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
