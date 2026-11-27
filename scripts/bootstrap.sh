#!/usr/bin/env bash
# Installs the tools needed to build Islet.
set -euo pipefail
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
brew list gh >/dev/null 2>&1 || brew install gh
xcode-select -p >/dev/null || { echo "Install Xcode from the App Store"; exit 1; }
xcodegen generate
# `peninsula` from any folder (test builds, releases), the same way as ascupload.
mkdir -p ~/.local/bin
ln -sf "$PWD/scripts/peninsula" ~/.local/bin/peninsula
echo "Done. Run: open Islet.xcodeproj, or peninsula (~/.local/bin must be on your PATH)"
