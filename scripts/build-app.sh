#!/usr/bin/env bash
# Builds a release BadgeBar.app into ./build.
#
# Usage: scripts/build-app.sh [signing identity]
# Without an identity the app is ad-hoc signed. macOS ties the Accessibility grant to the
# signature, so with ad-hoc signing you may need to re-grant access after each rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."
IDENTITY="${1:--}"
APP="build/BadgeBar.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/BadgeBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BadgeBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP"
