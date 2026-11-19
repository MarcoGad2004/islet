#!/usr/bin/env bash
# Publishes a new Islet version: scripts/release.sh 1.1
# Sets the version in project.yml, builds dist/Islet.dmg, commits, tags and creates a GitHub release with the DMG.
# Installed copies find it with Settings > Updates > Check for updates. Outward-facing: run it only when you mean it.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?usage: scripts/release.sh <version, e.g. 1.1>}"
B=$(git rev-list --count HEAD)
sed -i '' -E "s/(CFBundleShortVersionString: )\"[^\"]*\"/\1\"$V\"/; s/(CFBundleVersion: )\"[^\"]*\"/\1\"$B\"/" project.yml
./scripts/make-dmg.sh
git commit -m "Version $V" -- project.yml Sources/Islet/Info.plist
git tag "v$V"
git push origin main "v$V"
gh release create "v$V" dist/Islet.dmg --title "Islet $V" --notes "Islet $V"
echo "Released v$V"
