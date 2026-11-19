#!/usr/bin/env bash
# Builds a Release Islet.app and packs it into dist/Islet.dmg (drag to Applications).
# Personal-use build: signed with your Apple Development certificate (DEVELOPMENT_TEAM in project.yml), not
# notarized. Installing on this Mac works as is; on another Mac, right-click > Open the first time.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f Models/FaceEmbedding.mlmodel ] || ./scripts/fetch-model.sh
xcodegen generate >/dev/null

DERIVED="build/dmg-derived"
xcodebuild -scheme Islet -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" build | tail -3

APP="$DERIVED/Build/Products/Release/Islet.app"
[ -d "$APP" ] || { echo "Build failed: no Islet.app"; exit 1; }

STAGE="build/dmg-stage"
rm -rf "$STAGE" dist/Islet.dmg
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/Islet.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Islet" -srcfolder "$STAGE" -ov -format UDZO dist/Islet.dmg >/dev/null
echo "Created dist/Islet.dmg ($(du -h dist/Islet.dmg | cut -f1))"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Apple Development|TeamIdentifier" | head -2
