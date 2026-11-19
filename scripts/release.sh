#!/usr/bin/env bash
# Publishes a new Islet version: scripts/release.sh 1.1
# Sets the version in project.yml, builds dist/Islet.dmg, commits, tags and creates a GitHub release with the DMG.
# Installed copies find it with Settings > Updates > Check for updates. Outward-facing: run it only when you mean it.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?usage: scripts/release.sh <version, e.g. 1.1>}"
grep -q "^## $V " CHANGELOG.md || { echo "Add a ## $V section to CHANGELOG.md first"; exit 1; }
B=$(git rev-list --count HEAD)
sed -i '' -E "s/(CFBundleShortVersionString: )\"[^\"]*\"/\1\"$V\"/; s/(CFBundleVersion: )\"[^\"]*\"/\1\"$B\"/" project.yml
./scripts/make-dmg.sh
git commit -m "Version $V" -- project.yml Sources/Islet/Info.plist CHANGELOG.md
git tag "v$V"
git push origin main "v$V"
NOTES=$(mktemp)
awk -v v="$V" '$0 ~ "^## "v" " {on=1; next} /^## / {on=0} on' CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || { echo "No CHANGELOG.md section for $V"; exit 1; }
gh release create "v$V" dist/Islet.dmg --title "Islet $V" --notes-file "$NOTES"
echo "Released v$V"
