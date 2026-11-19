#!/usr/bin/env bash
# Builds the vendored mediaremote-adapter framework (BSD-3, vendor/mediaremote-adapter, pinned commit 14eed93)
# without cmake, and copies it plus its perl script into the app's Resources.
# Usage: build-mediaremote.sh <destination Resources dir>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vendor/mediaremote-adapter"
OUT="${DERIVED_FILE_DIR:-$ROOT/build}/MediaRemoteAdapter.framework"
DEST="${1:?destination Resources dir}"
FW="$OUT/Versions/A"
rm -rf "$OUT"; mkdir -p "$FW/Headers" "$FW/Resources"
FILES=$(cd "$SRC" && ls src/adapter/*.m src/private/MediaRemote.m src/utility/Debounce.m src/utility/helpers.m | grep -v 'src/adapter/test.m' ; echo src/adapter/test.m)
cd "$SRC"
xcrun clang -dynamiclib -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  -I include -I src -I src/adapter -I src/private -I src/utility \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  $FILES -o "$FW/MediaRemoteAdapter"
cp include/MediaRemoteAdapter.h "$FW/Headers/"
cat > "$FW/Resources/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string><key>CFBundleName</key><string>MediaRemoteAdapter</string><key>CFBundleExecutable</key><string>MediaRemoteAdapter</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleVersion</key><string>0.1.0</string></dict></plist>
PL
ln -sfn A "$OUT/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$OUT/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$OUT/Resources"
ln -sfn Versions/Current/Headers "$OUT/Headers"
mkdir -p "$DEST"
rm -rf "$DEST/MediaRemoteAdapter.framework"
cp -R "$OUT" "$DEST/MediaRemoteAdapter.framework"
cp bin/mediaremote-adapter.pl "$DEST/mediaremote-adapter.pl"
