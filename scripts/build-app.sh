#!/usr/bin/env bash
# Builds a release BadgeBar.app into ./build.
#
# Usage: scripts/build-app.sh [signing identity]
# Without an identity it uses "BadgeBar Local Signing" (see scripts/create-signing-cert.sh)
# if present, otherwise ad-hoc signing. macOS ties privacy permissions to the signature, and
# ad-hoc signatures change on every build, so prefer a stable identity.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ -n "${1:-}" ]; then
  IDENTITY="$1"
elif security find-certificate -c "BadgeBar Local Signing" >/dev/null 2>&1; then
  IDENTITY="BadgeBar Local Signing"
else
  IDENTITY="-"
  echo "warning: ad-hoc signing; permissions will reset on every rebuild (run scripts/create-signing-cert.sh)" >&2
fi
APP="build/BadgeBar.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/BadgeBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BadgeBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP"
