#!/usr/bin/env bash
# Installs the tools needed to build Islet.
set -euo pipefail
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
brew list gh >/dev/null 2>&1 || brew install gh
xcode-select -p >/dev/null || { echo "Install Xcode from the App Store"; exit 1; }
xcodegen generate
echo "Done. Run: open Islet.xcodeproj"
