#!/usr/bin/env bash
# Labels a build made between releases, so Settings can say what it is: "1.4 test build (0c0bbea)", the unreleased
# version at the top of CHANGELOG.md and the commit (+ when there were uncommitted changes). The real version number
# stays the last release's until scripts/release.sh sets it, so the updater still offers the release itself.
# Release builds (the version already matches CHANGELOG.md's newest section) get no label.
set -uo pipefail
PLIST="$1"
V=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST" 2>/dev/null)
NEXT=$(grep -m1 -E '^## [0-9.]+ \(unreleased\)' "$SRCROOT/CHANGELOG.md" | awk '{print $2}')
/usr/libexec/PlistBuddy -c "Delete :IsletBuildLabel" "$PLIST" >/dev/null 2>&1
if [ -n "$NEXT" ] && [ "$NEXT" != "$V" ]; then
  HASH=$(git -C "$SRCROOT" rev-parse --short HEAD 2>/dev/null)
  git -C "$SRCROOT" diff --quiet HEAD -- Sources 2>/dev/null || HASH="$HASH+"
  /usr/libexec/PlistBuddy -c "Add :IsletBuildLabel string $NEXT test build ($HASH)" "$PLIST"
fi
exit 0
