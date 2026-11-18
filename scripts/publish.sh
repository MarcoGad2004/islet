#!/usr/bin/env bash
# One-time: create a PRIVATE GitHub repo from this folder and push.
set -euo pipefail
command -v gh >/dev/null || brew install gh
gh auth status >/dev/null 2>&1 || gh auth login
git init -b main
git add -A
git commit -m "Initial project setup"
gh repo create islet --private --source=. --remote=origin --push
