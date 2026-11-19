#!/usr/bin/env bash
# Builds a Release Islet.app and packs it into dist/Islet.dmg (drag to Applications).
# With a "Developer ID Application" certificate in the Keychain, it re-signs the app with it and has Apple notarize
# the DMG, so it opens on any Mac without a warning. Notarizing uses the Keychain profile "islet-notary", saved once with
#   xcrun notarytool store-credentials islet-notary --apple-id <Apple ID> --team-id X9Q5Y948RX
# (it asks for an app-specific password from account.apple.com). Without the certificate the DMG is signed with the
# Apple Development certificate as before, and other Macs need System Settings > Privacy & Security > Open Anyway.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f Models/FaceEmbedding.mlmodel ] || ./scripts/fetch-model.sh
xcodegen generate >/dev/null

DERIVED="build/dmg-derived"
xcodebuild -scheme Islet -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" build | tail -3

APP="$DERIVED/Build/Products/Release/Islet.app"
[ -d "$APP" ] || { echo "Build failed: no Islet.app"; exit 1; }

NOTARY_PROFILE="islet-notary"
DEVID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [ -n "$DEVID" ]; then
  # Inside out: the media adapter (loaded by perl from Resources), then the app with its entitlements.
  SIGN=(codesign --force --timestamp --options runtime --sign "$DEVID")
  "${SIGN[@]}" "$APP/Contents/Resources/MediaRemoteAdapter.framework"
  "${SIGN[@]}" --entitlements Sources/Islet/Islet.entitlements "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Signed with $DEVID"
fi

STAGE="build/dmg-stage"
rm -rf "$STAGE" dist/Islet.dmg
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/Islet.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Islet" -srcfolder "$STAGE" -ov -format UDZO dist/Islet.dmg >/dev/null
echo "Created dist/Islet.dmg ($(du -h dist/Islet.dmg | cut -f1))"

if [ -n "$DEVID" ]; then
  codesign --force --timestamp --sign "$DEVID" dist/Islet.dmg
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Notarizing (usually a few minutes)…"
    xcrun notarytool submit dist/Islet.dmg --keychain-profile "$NOTARY_PROFILE" --wait | tee build/notary.log
    grep -q "status: Accepted" build/notary.log || { echo "Notarization failed; see: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"; exit 1; }
    xcrun stapler staple dist/Islet.dmg
    spctl -a -t open --context context:primary-signature -v dist/Islet.dmg
  else
    echo "Not notarized: no \"$NOTARY_PROFILE\" Keychain profile (see the top of this script)."
  fi
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority=(Developer ID|Apple Development)|TeamIdentifier" | head -2
