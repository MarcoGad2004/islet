# Islet

A personal macOS app that turns the MacBook Pro notch into a dynamic, interactive "island" (notifications, now playing, search, quick controls). Built for my own use as a replacement for an unmaintained notch app.

> Status: **v1 design locked ([docs/DESIGN.md](docs/DESIGN.md)). No app code yet.**

## v1 features
- Media: now playing with controls
- Charging and battery: charger connected, fully charged, low battery
- Volume and brightness: replaces the system display with a 16-step bar
- Face unlock: unlocks this Mac's lock screen with the camera (convenience, weaker than Touch ID)
- Unlock animation after any unlock

The island grows beside the camera when the menu bar has room, otherwise it drops below the notch
so it never covers menus. Two-finger swipe up over it to hide, down to bring it back.

Lightweight, native, no analytics; the only network use is the update check you click. Runs on my 14" MacBook Pro (Apple silicon).

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
- [docs/DESIGN.md](docs/DESIGN.md): locked v1 design (source of truth)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): planned structure
- [docs/ROADMAP.md](docs/ROADMAP.md): milestones
- [docs/RESEARCH.md](docs/RESEARCH.md): open technical questions to verify

## License
MIT, see [LICENSE](LICENSE). The spoof model in `Models/AntiSpoof.mlpackage` is converted from Minivision's
[Silent-Face-Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) (Apache-2.0, see
[Models/AntiSpoof-LICENSE.txt](Models/AntiSpoof-LICENSE.txt)).


## Install (DMG)

```bash
scripts/make-dmg.sh      # builds a Release app and writes dist/Islet.dmg
```

Open `dist/Islet.dmg`, drag Islet to Applications, launch it, then allow Accessibility (Settings in the
menu bar item shows what is missing) and turn on "Open Islet at login". The face model is fetched by
`scripts/fetch-model.sh` (the DMG script runs it for you). Not notarized: it is for this Mac.
