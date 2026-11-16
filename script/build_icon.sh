#!/usr/bin/env bash
set -euo pipefail
ICON_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../Assets/AppIcon" && pwd)"
ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp/}service-watch-icon.XXXXXX")"
cleanup_icon() { /usr/bin/find "$ICON_WORK" -type f -delete; /usr/bin/find "$ICON_WORK" -depth -type d -empty -delete; }
trap cleanup_icon EXIT
mkdir -p "$ICON_WORK/AppIcon.iconset"
for side in 16 32 128 256 512; do
  /usr/bin/sips -z "$side" "$side" "$ICON_ROOT/AppIcon-source.png" --out "$ICON_WORK/AppIcon.iconset/icon_${side}x${side}.png" >/dev/null
  retina=$((side * 2))
  /usr/bin/sips -z "$retina" "$retina" "$ICON_ROOT/AppIcon-source.png" --out "$ICON_WORK/AppIcon.iconset/icon_${side}x${side}@2x.png" >/dev/null
done
/usr/bin/iconutil --convert icns "$ICON_WORK/AppIcon.iconset" --output "$ICON_ROOT/AppIcon.icns"
/usr/bin/sips -z 1024 1024 "$ICON_ROOT/AppIcon-source.png" --out "$ICON_ROOT/AppIcon-1024.png" >/dev/null
