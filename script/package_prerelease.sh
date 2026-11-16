#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_NUMBER="3"
VERSION="0.1.2"
APP_NAME="续期 Open"
BUNDLE_NAME="$APP_NAME.app"
BUNDLE_ID="com.sevacenix.ServiceWatch.Open"
OUTPUT_DIR="${1:-$ROOT_DIR/dist/$VERSION}"
cd "$ROOT_DIR"

if [[ -e "$OUTPUT_DIR" ]]; then
  echo "Refusing to replace existing release: $OUTPUT_DIR" >&2
  exit 1
fi
./script/build_icon.sh
swift build -c release --arch arm64
BUILD_BINARY="$(swift build -c release --arch arm64 --show-bin-path)/ServiceWatch"

# Stage outside Documents: file-provider Finder metadata must not alter a sealed bundle.
STAGE_PARENT="$HOME/Library/Caches/$BUNDLE_ID/Packaging"
mkdir -p "$STAGE_PARENT"
STAGE="$(mktemp -d "$STAGE_PARENT/prerelease.XXXXXX")"
cleanup_stage() {
  /usr/bin/find "$STAGE" -type f -delete
  /usr/bin/find "$STAGE" -type l -delete
  /usr/bin/find "$STAGE" -depth -type d -empty -delete
}
trap cleanup_stage EXIT
APP_BUNDLE="$STAGE/$BUNDLE_NAME"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp -X Sources/ServiceWatch/Resources/English.json "$APP_BUNDLE/Contents/Resources/English.json"
cp -X "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/ServiceWatch"
# Release binaries do not need debug symbols with build machine source paths.
/usr/bin/strip -S "$APP_BUNDLE/Contents/MacOS/ServiceWatch"
cp -X Assets/AppIcon/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp -X LICENSE "$APP_BUNDLE/Contents/Resources/LICENSE"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ServiceWatch</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>续期</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>ServiceWatchDisplayVersion</key><string>$VERSION</string>
<key>ServiceWatchReleaseChannel</key><string>Open</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

mkdir -p "$(dirname "$OUTPUT_DIR")"
mkdir "$OUTPUT_DIR"
cp -X RELEASE-NOTES.md "$OUTPUT_DIR/使用说明.md"
/usr/bin/ditto -c -k --keepParent --norsrc "$APP_BUNDLE" "$OUTPUT_DIR/ServiceWatch-$VERSION-macOS-arm64.zip"

DMG_ROOT="$STAGE/DiskImage"
mkdir "$DMG_ROOT"
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$DMG_ROOT/$BUNDLE_NAME"
cp -X RELEASE-NOTES.md "$DMG_ROOT/使用说明.md"
ln -s /Applications "$DMG_ROOT/Applications"
/usr/bin/codesign --verify --deep --strict "$DMG_ROOT/$BUNDLE_NAME"
/usr/bin/hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -fs HFS+ -format UDZO "$OUTPUT_DIR/ServiceWatch-$VERSION-macOS-arm64.dmg"

/usr/bin/python3 - "$OUTPUT_DIR" "$VERSION" "$BUILD_NUMBER" <<'PY'
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

destination, version, build = sys.argv[1:]
folder = pathlib.Path(destination)
artifacts = []
for path in sorted(folder.iterdir()):
    if path.is_file():
        artifacts.append({"name": path.name, "bytes": path.stat().st_size,
                          "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
manifest = {
    "app": "续期 Open", "version": version, "build": build,
    "bundleIdentifier": "com.sevacenix.ServiceWatch.Open",
    "architecture": "arm64", "minimumMacOS": "14.0",
    "signing": "ad-hoc, hardened runtime", "notarized": False,
    "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
    "artifacts": artifacts,
}
(folder / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
checksums = [f'{item["sha256"]}  {item["name"]}' for item in artifacts]
(folder / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n")
PY
echo "Packaged: $OUTPUT_DIR"
