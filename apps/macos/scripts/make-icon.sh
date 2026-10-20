#!/usr/bin/env bash
# Renders the fixed light and dark versions of Resources/AppIcon.icon (the Icon Composer
# document the app icon is built from) for the App Icon choice in Settings, and a 1024 px
# Resources/AppIcon.png for the README. Needs Xcode with Icon Composer.
#
# Edit the icon itself in Icon Composer (Xcode ▸ Open Developer Tool ▸ Icon Composer).
set -euo pipefail
cd "$(dirname "$0")/.."
ICTOOL="$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool"

render() {
  "$ICTOOL" Resources/AppIcon.icon --export-image --output-file "$2" \
    --platform macOS --rendition "$1" --width "$3" --height "$3" --scale 1 >/dev/null
}
render Default Resources/AppIcon-light.png 512
render Dark Resources/AppIcon-dark.png 512
render Default Resources/AppIcon.png 1024
echo "Rendered Resources/AppIcon-light.png, AppIcon-dark.png and AppIcon.png"
