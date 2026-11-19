# Notes for Claude: Islet

Islet turns the MacBook Pro notch into a dynamic island. It is a personal app (not for the App
Store). The general workflow rules in the owner's global CLAUDE.md apply (work on `main`, commit
only your files, build before committing).

## Start here

1. [docs/DESIGN.md](docs/DESIGN.md): the locked v1 design. It is the source of truth; don't change
   behaviour or visuals without asking the owner.
2. [docs/ROADMAP.md](docs/ROADMAP.md): build order. Work milestone by milestone and tick items off.
3. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how it's structured.
4. [docs/RESEARCH.md](docs/RESEARCH.md): open technical questions. Record findings there.

The interactive mockups are at <https://claude.ai/artifact/9gDTDbkfLsf2UXTDE6WJ8U> (read it with
the Artifact tool, not a web fetch). The "v1 prototype" artboard shows the motion.

## Project

- Swift 6, SwiftUI views in an AppKit `NSPanel`, macOS 14+.
- The Xcode project is generated: edit `project.yml`, then run `xcodegen generate`. Don't commit
  `Islet.xcodeproj`.
- Build: `xcodegen generate && xcodebuild -scheme Islet -destination 'platform=macOS' build`.
- No analytics. No network access except Settings > Updates, which only runs when clicked and goes through `gh` to this repo's releases (`scripts/release.sh <version>` publishes one, using the matching section of CHANGELOG.md as its notes; keep CHANGELOG.md up to date as features land).

## Decisions already made

- Timer, file shelf and calendar are out of v1.
- Face unlock stores the login password in the Keychain and types it into the lock screen after a
  face match. The owner accepts it is weaker than Touch ID. It must never be used for anything but
  this Mac's lock screen. Do the M2 feasibility spike before building any of its UI.
- Volume and brightness always use the chin layout; other compact content uses wings only when the
  menu bar width check says they fit.
