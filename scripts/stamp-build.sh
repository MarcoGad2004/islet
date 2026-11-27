#!/usr/bin/env bash
# Records which commit a build was made from (IsletCommit, with + when Sources had uncommitted changes), so
# scripts/peninsula can tell whether a DMG holds the build it is about to release.
# Labels a build made between releases, so Settings can say what it is: "1.4 test build (0c0bbea)", the version of
# CHANGELOG.md's newest section and the commit. The real version number stays the last release's until
# scripts/peninsula release sets it, so the updater still offers the release itself.
# Release builds (the version already matches CHANGELOG.md's newest section) get no label.
set -uo pipefail
PLIST="$1"
V=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST" 2>/dev/null)
# The newest section, whether it says "(unreleased)" or already has its date.
NEXT=$(grep -m1 -E '^## [0-9]' "$SRCROOT/CHANGELOG.md" | awk '{print $2}')
HASH=$(git -C "$SRCROOT" rev-parse --short HEAD 2>/dev/null)
git -C "$SRCROOT" diff --quiet HEAD -- Sources ':!Sources/Islet/Info.plist' 2>/dev/null || HASH="$HASH+"
/usr/libexec/PlistBuddy -c "Delete :IsletBuildLabel" "$PLIST" >/dev/null 2>&1
/usr/libexec/PlistBuddy -c "Delete :IsletCommit" "$PLIST" >/dev/null 2>&1
[ -n "$HASH" ] && /usr/libexec/PlistBuddy -c "Add :IsletCommit string $HASH" "$PLIST"
if [ -n "$NEXT" ] && [ "$NEXT" != "$V" ]; then
  /usr/libexec/PlistBuddy -c "Add :IsletBuildLabel string $NEXT test build ($HASH)" "$PLIST"
fi
exit 0
