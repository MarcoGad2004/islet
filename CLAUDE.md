# Notes for Claude: Islet

Islet turns the MacBook Pro notch into a dynamic island. Since 1.5 the app is called **Dynamic Peninsula** (owner's
decision, 2026-11-23, name only): the product, its visible text and the release DMG use that name, while the bundle ID
(`com.marcogad.islet`), the Swift module, the targets, the repo and the code keep "Islet". Releases carry both
`Dynamic Peninsula.dmg` and `Islet.dmg` (for pre-1.5 copies, whose updater only knows that name). It is a personal app (not for the App
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
- No analytics. No network access except updates and Shazam (only while it listens, after a press or swipe: ShazamKit
  sends a sound signature and the cover is downloaded; owner's request, 2026-11-23) and the Wi-Fi panel's speed test (macOS's `networkQuality`, only when Run speed test is pressed). Updates: Islet reads this public repo's latest release from GitHub's API (no account or `gh` needed) when Check for updates is clicked, and on its own about every 6 hours unless Settings > Updates > "Check for updates automatically" is off (owner's decision, 2026-11-19) (`peninsula release` publishes one, using the matching section of CHANGELOG.md as its notes and dating its heading; keep CHANGELOG.md up to date as features land).

## Decisions already made

- Timer, file shelf and calendar are out of v1.
- Face unlock stores the login password in the Keychain and types it into the lock screen after a
  face match. The owner accepts it is weaker than Touch ID. It must never be used for anything but
  this Mac's lock screen. Do the M2 feasibility spike before building any of its UI.
- Volume and brightness always use the chin layout; other compact content uses wings only when the
  menu bar width check says they fit.

## Running a test build on the owner's Mac (every session follows this)

`peninsula` (scripts/peninsula, linked into ~/.local/bin by scripts/bootstrap.sh, so it runs from any folder) does
the whole process; run with no arguments it shows what is installed, released and pending and
offers a menu. Keep exactly ONE copy of the app on the Mac: `/Applications/Dynamic Peninsula.app`.

- When the owner asks to run or rebuild the test copy: `peninsula install` (it asks nothing). It builds Release
  signed with the Developer ID certificate (the same identity as releases, which keeps the permissions macOS gave the
  app), quits the app, replaces the copy in /Applications in place, deletes the build folders and Islet's DerivedData,
  relaunches it, and says what is installed. Never launch a test build from a build folder.
- `peninsula revert` puts the released build back (downloaded from GitHub and checked) when testing is done.
- `peninsula status` shows the state without changing anything.
- Releasing: `peninsula release`, only when the owner asks. It asks the version (and whether to install it) first,
  then runs unattended; the owner runs it in a
  terminal (hand them the command). It is resumable and reuses DMGs that are already notarized.

For your own build checks (compiling, running tests) use a throwaway `-derivedDataPath` and delete it afterwards.
