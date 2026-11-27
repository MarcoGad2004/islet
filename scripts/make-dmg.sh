#!/usr/bin/env bash
# Kept for habit: scripts/peninsula dmg builds the current tree into signed, notarized DMGs in dist/
# (--app-only stops at the signed app). See scripts/peninsula help.
exec "$(dirname "$0")/peninsula" dmg "$@"
