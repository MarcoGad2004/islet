#!/usr/bin/env bash
# Builds a Release "Dynamic Peninsula.app" and packs it into "dist/Dynamic Peninsula.dmg" (drag to Applications).
# It also makes dist/Islet.dmg, the same app named Islet.app, for copies from before the 1.5 rename: their updater
# only looks for that download and that name. The app names itself Dynamic Peninsula.app at the next update.
# With a "Developer ID Application" certificate in the Keychain, it re-signs the app with it and has Apple notarize
# the DMG, so it opens on any Mac without a warning. Notarizing uses the Keychain profile "islet-notary", saved once with
#   xcrun notarytool store-credentials islet-notary --apple-id <Apple ID> --team-id X9Q5Y948RX
# (it asks for an app-specific password from account.apple.com). `--app-only` stops at the signed app, for trying it
# locally. Without the certificate the DMG is signed with the
# Apple Development certificate as before, and other Macs need System Settings > Privacy & Security > Open Anyway.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f Models/FaceEmbedding.mlmodel ] || ./scripts/fetch-model.sh
xcodegen generate >/dev/null

DERIVED="build/dmg-derived"
xcodebuild -scheme Islet -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" build | tail -3

APP="$DERIVED/Build/Products/Release/Dynamic Peninsula.app"
[ -d "$APP" ] || { echo "Build failed: no Dynamic Peninsula.app"; exit 1; }

NOTARY_PROFILE="islet-notary"
DEVID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [ -n "$DEVID" ]; then
  # Inside out: the media adapter (loaded by perl from Resources), the fan helper (it and the app each check the other
  # is signed by the same team), then the app with its entitlements.
  SIGN=(codesign --force --timestamp --options runtime --sign "$DEVID")
  "${SIGN[@]}" "$APP/Contents/Resources/MediaRemoteAdapter.framework"
  "${SIGN[@]}" --identifier com.marcogad.islet.fanhelper "$APP/Contents/MacOS/IsletFanHelper"
  "${SIGN[@]}" --entitlements Sources/Islet/Islet.entitlements "$APP"
  codesign --verify --deep --strict "$APP"
  echo "Signed with $DEVID"
fi

# --app-only: stop at the signed app (to try it in /Applications), without the DMGs or notarizing.
if [ "${1:-}" = "--app-only" ]; then
  echo "App: $APP"
  exit 0
fi

# pack <dmg> <app name inside> <volume name>
pack() {
  local DMG="$1" NAME="$2" VOL="$3" STAGE="build/dmg-stage"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE" dist
  ditto "$APP" "$STAGE/$NAME"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
  if [ -n "$DEVID" ]; then
    codesign --force --timestamp --sign "$DEVID" "$DMG"
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
      echo "Notarizing $DMG (usually a few minutes)…"
      xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait | tee build/notary.log
      grep -q "status: Accepted" build/notary.log || { echo "Notarization failed; see: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"; exit 1; }
      xcrun stapler staple "$DMG"
      spctl -a -t open --context context:primary-signature -v "$DMG"
    else
      echo "Not notarized: no \"$NOTARY_PROFILE\" Keychain profile (see the top of this script)."
    fi
  fi
}

pack "dist/Dynamic Peninsula.dmg" "Dynamic Peninsula.app" "Dynamic Peninsula"
pack "dist/Islet.dmg" "Islet.app" "Islet"
codesign -dv "$APP" 2>&1 | grep -E "Authority=(Developer ID|Apple Development)|TeamIdentifier" | head -2
