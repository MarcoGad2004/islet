#!/usr/bin/env bash
# Publishes a new Dynamic Peninsula (formerly Islet) version: scripts/release.sh 1.1
# Sets the version in project.yml, builds "dist/Dynamic Peninsula.dmg" and dist/Islet.dmg (for pre-1.5 copies), checks
# they are Developer ID signed and notarized, uploads them to a DRAFT GitHub release, then commits, tags, pushes and
# publishes the draft. Installed copies find it with Settings > Updates > Check for updates.
# Outward-facing: run it only when you mean it. If it stops part way, fix the cause and run it again: every step is
# skipped when it is already done, and nothing is public until the last one.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?usage: scripts/release.sh <version, e.g. 1.1>}"
TAG="v$V"
FILES=(project.yml Sources/Islet/Info.plist CHANGELOG.md)

# 1. Everything that can be wrong, before anything is changed.
grep -q "^## $V " CHANGELOG.md || { echo "Add a ## $V section to CHANGELOG.md first"; exit 1; }
NOTES=$(mktemp)
awk -v v="$V" '$0 ~ "^## "v" " {on=1; next} /^## / {on=0} on' CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || { echo "No CHANGELOG.md section for $V"; exit 1; }
for tool in gh xcodegen xcrun; do command -v "$tool" >/dev/null || { echo "$tool is not installed"; exit 1; }; done
gh auth status >/dev/null 2>&1 || { echo "gh isn't signed in (gh auth login)"; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "Release from main"; exit 1; }
git fetch -q origin main
git merge-base --is-ancestor origin/main HEAD || { echo "main is behind origin/main: pull first"; exit 1; }
# project.yml and CHANGELOG.md are hand-edited: they must already be committed (Info.plist is generated, below).
git diff --quiet HEAD -- project.yml CHANGELOG.md 2>/dev/null || [ "$(grep -c "CFBundleShortVersionString: \"$V\"" project.yml)" = 1 ] \
  || { echo "project.yml or CHANGELOG.md has uncommitted changes: commit or discard them first"; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then
  [ "$(gh release view "$TAG" --json isDraft -q .isDraft)" = true ] || { echo "$TAG is already published"; exit 1; }
fi

# 2. Version and build.
B=$(git rev-list --count HEAD)
sed -i '' -E "s/(CFBundleShortVersionString: )\"[^\"]*\"/\1\"$V\"/; s/(CFBundleVersion: )\"[^\"]*\"/\1\"$B\"/" project.yml

# 3. Build, sign, notarize; then prove it before anything is uploaded.
REQUIRE_NOTARIZED=1 ./scripts/make-dmg.sh
for DMG in "dist/Dynamic Peninsula.dmg" dist/Islet.dmg; do
  SIGINFO=$(codesign -dvv "$DMG" 2>&1 || true)   # captured first: grep -q closing the pipe early would fail under pipefail
  case "$SIGINFO" in *"Authority=Developer ID Application"*) ;; *) echo "$DMG isn't Developer ID signed"; exit 1;; esac
  xcrun stapler validate "$DMG" >/dev/null || { echo "$DMG isn't notarized and stapled"; exit 1; }
  spctl -a -t open --context context:primary-signature "$DMG" 2>/dev/null || { echo "Gatekeeper rejects $DMG"; exit 1; }
done

# 4. A draft release with the DMGs (not public, no tag yet).
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "dist/Dynamic Peninsula.dmg" dist/Islet.dmg --clobber
  gh release edit "$TAG" --title "Dynamic Peninsula $V" --notes-file "$NOTES"
else
  gh release create "$TAG" "dist/Dynamic Peninsula.dmg" dist/Islet.dmg --draft --title "Dynamic Peninsula $V" --notes-file "$NOTES"
fi

# 5. Commit, tag, push, and only then publish.
git diff --quiet HEAD -- "${FILES[@]}" || git commit -m "Version $V" -- "${FILES[@]}"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git tag "$TAG"
git push origin main "$TAG"
gh release edit "$TAG" --draft=false --latest
echo "Released $TAG"
