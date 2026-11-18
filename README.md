# Islet

A personal macOS app that turns the MacBook Pro notch into a dynamic, interactive "island" (live activities, now playing, quick controls). Built for my own use as a replacement for an unmaintained notch app.

> Status: **project setup only. No app code yet.**

## Goals
- Expand/collapse smoothly from the physical notch on hover or click
- Live activities: now playing, timers, calendar, battery/charging, file shelf
- Lightweight, native, no analytics, no network calls by default
- Runs on my MacBook Pro (Apple silicon, macOS 14+)

## Non-goals
- App Store distribution
- Supporting Macs without a notch (maybe later, low priority)
- Copying any assets, code, or branding from other notch apps

## Tech stack
- Swift 6, SwiftUI for views, AppKit (`NSPanel`) for the notch window
- Xcode project generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Minimum target: macOS 14

## Getting started
```bash
brew install xcodegen
xcodegen generate
open Islet.xcodeproj
```
Requires Xcode (full app, not just Command Line Tools).

## Docs
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): planned structure
- [docs/ROADMAP.md](docs/ROADMAP.md): milestones
- [docs/RESEARCH.md](docs/RESEARCH.md): open technical questions to verify

## License
MIT, see [LICENSE](LICENSE).
