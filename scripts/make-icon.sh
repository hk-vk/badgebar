#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns and AppIcon.png from Resources/AppIcon.svg, and
# Resources/AppIcon-dark.png (used for the Dock in dark mode) from AppIcon-dark.svg.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift scripts/make-icon.swift Resources/AppIcon.svg "$TMP/icon.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$TMP/icon.png" Resources/AppIcon.png
swift scripts/make-icon.swift Resources/AppIcon-dark.svg "$TMP/icon-dark.png"
sips -z 512 512 "$TMP/icon-dark.png" --out Resources/AppIcon-dark.png >/dev/null
echo "Wrote Resources/AppIcon.icns"
