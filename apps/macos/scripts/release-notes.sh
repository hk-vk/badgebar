#!/usr/bin/env bash
# Prints the GitHub release notes, one line per paragraph since GitHub keeps line breaks for a tag: its CHANGELOG.md section, how to install, and the
# app's commits since the previous tag.
#
# Usage: scripts/release-notes.sh v0.2.0 [path/to/BadgeBar-0.2.0.zip]
set -euo pipefail

TAG="$1"
ZIP="${2:-}"
VERSION="${TAG#v}"
ROOT="$(git rev-parse --show-toplevel)"
REPO_URL="https://github.com/hk-vk/badgebar"

# The "## <version>" section of the changelog, without its heading.
NOTES="$(awk -v v="## $VERSION" '$0 == v { on = 1; next } /^## / { on = 0 } on' "$ROOT/CHANGELOG.md")"
if [ -z "${NOTES//[[:space:]]/}" ]; then
  echo "error: CHANGELOG.md has no section for $VERSION" >&2
  exit 1
fi

PREVIOUS="$(git describe --tags --abbrev=0 --match 'v*' "$TAG^" 2>/dev/null || true)"
RANGE="${PREVIOUS:+$PREVIOUS..}$TAG"

printf '%s\n\n' "$(sed -e '/./,$!d' <<<"$NOTES")"

cat <<EOF
## Install

\`\`\`sh
brew install --cask hk-vk/tap/badgebar
\`\`\`

Already installed with Homebrew? Run \`brew upgrade --cask badgebar\`. Your permissions carry over.

Or download BadgeBar-$VERSION.zip below and move BadgeBar to Applications. BadgeBar isn't notarized, so the first time you open a downloaded copy, click *Open Anyway* in System Settings ▸ Privacy & Security.
EOF
if [ -n "$ZIP" ]; then
  printf '\nSHA-256: `%s`\n' "$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
fi

printf '\n## Commits\n\n'
# Only commits that touch the app. The first release lists everything, from before the app moved
# into apps/macos.
git log --no-merges --reverse --format='- %s (%h)' "$RANGE" ${PREVIOUS:+-- "$ROOT/apps/macos"}
if [ -n "$PREVIOUS" ]; then
  printf '\nFull list of changes: %s/compare/%s...%s\n' "$REPO_URL" "$PREVIOUS" "$TAG"
fi
