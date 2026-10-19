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

# SwiftPM records the deployment target (14.0) as the SDK version in the binary, and macOS
# then draws the app with its old, pre-Liquid Glass controls. Record the real SDK instead.
SDK_VERSION="$(xcrun --show-sdk-version)"
LINK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")

swift build -c release --arch arm64 --arch x86_64 "${LINK_FLAGS[@]}"
BIN="$(swift build -c release --arch arm64 --arch x86_64 "${LINK_FLAGS[@]}" --show-bin-path)/BadgeBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BadgeBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The icon is an Icon Composer document. actool compiles it into Assets.car, which macOS
# renders with Liquid Glass in the user's icon style (default, dark, clear, tinted), plus an
# AppIcon.icns for older systems.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$(mktemp -d)/icon.plist" >/dev/null
# Fixed light and dark renderings, for the App Icon choice in Settings.
cp Resources/AppIcon-light.png Resources/AppIcon-dark.png "$APP/Contents/Resources/"

codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP"
