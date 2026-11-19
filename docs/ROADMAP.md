# Roadmap

Design is locked: see [DESIGN.md](DESIGN.md). Build in this order; each milestone should run from
Xcode on the MacBook Pro before moving on.

## M0: Repo setup
- [x] Repo, docs, license, gitignore, XcodeGen config
- [x] v1 design locked (DESIGN.md, mockup canvas)

## M1: Notch window and island shape
- [x] Generate the Xcode project; app launches as an agent app with a menu bar item (Settings, Pause, Quit)
- [x] Measure the notch from `NSScreen`; handle display changes and lid closed
- [x] Non-activating panel above the menu bar, on all Spaces and over full-screen apps
- [ ] Clicks outside the island pass through
- [x] Island `Shape` with stem, body and inner curves, all animatable
- [x] Closed, hover peek, wings, chin, expanded shapes with the flow-down/bubble-out motion (shapes checked on screen; tune the motion by eye)
- [ ] Click to open, collapse on leave (1 s), click outside, Esc
- [ ] Two-finger swipe up/down

> M1 status: everything above is built. Still to try by hand on the MacBook: click-through outside the
> island, hover peek, click/Esc/click-outside/1 s collapse, and the two-finger swipe direction (see
> RESEARCH.md items 3 and 4). In Debug builds the menu bar item has a "Show shape" menu, and
> `-IsletDebugShape wings|chin|scan|expanded` starts with a shape showing.

## M2: Face unlock spike (highest risk, do early)
Throwaway test app or debug menu, no UI polish. Answer each question in RESEARCH.md §Face unlock
and record the results there. If any blocker can't be solved, face unlock is dropped from v1 and
the unlock animation still ships.

## M3: Menu bar width check
- [x] Read front app menu frames (Accessibility) and status-item bounds
- [x] Wings vs chin decision, re-checked on app switch and menu changes; chin when no permission

## M4: Charging and battery
- [x] Power source notifications; connected, full, low 20%/10%
- [x] Wings and chin views, bolt pop, timings

## M5: Volume and brightness
- [x] Catch volume, mute and brightness keys, apply the change, suppress the system display
- [x] Chin HUD with the 16-step bar; mute state
- [x] Expanded Display and Sound page with battery block, sliders, output picker

## M6: Media
- [x] Now playing source (see RESEARCH.md §Now playing)
- [x] Wings and chin views, level bars, pause state, hide after 30 s
- [x] Expanded media page with controls and scrubber
- [x] Swipe up to hide media; swipe down to bring it back; green dot hint

## M7: Unlock animation
- [x] Listen for screen unlock; play the lock-opens sequence in wings or chin

## M8: Face unlock (M2 passed except Q13: the scan has no visuals over the lock screen)
- [x] Settings: enrol face (after Touch ID/password), store login password in the Keychain (island enrolment animation, test recognition and threshold slider included)
- [x] On lock: scan, match, type password; 3 tries (needs a real lock test; blink liveness still to do)
- [x] Face scan animation (looking, match, no match); visible over the lock screen only if the SkyLight space works (RESEARCH.md Q13)

## M9: Polish
- [x] Settings window, launch at login, permission prompts and status
- [x] Priority and hand-back between events
- [ ] Tune springs and timings on the real display

## M10: Control Center page (v1.1)
- [ ] Spike on this Mac (RESEARCH.md Q16-Q21): Wi-Fi scan/join (Location), Bluetooth connect and power, Focus read and
      set, AirDrop mode, mirroring, Night Shift / True Tone / Dark Mode. Record what works, per control.
- [ ] Layout: header battery chip, five tiles, two condensed sliders; tap vs drag; expand and back
- [ ] Display detail (brightness, Dark Mode, Night Shift, True Tone) and Sound detail (volume, output devices)
- [ ] Wi-Fi, Bluetooth, Focus, AirDrop, Mirroring tiles and their detail views, each with a Settings-pane fallback
- [ ] Permissions in onboarding and Settings (Location, Full Disk Access for reading Focus if needed); how to hide the
      system Control Center icon
- [ ] Ship as v1.1 (`scripts/release.sh 1.1`)

## Distribution
- [x] `scripts/make-dmg.sh` builds a Release app and packs `dist/Islet.dmg` (see README).

> Built but not yet exercised on real hardware: the menu bar width check on varied apps, charger and
> low-battery events, volume/brightness keys, media controls and scrubbing, and the unlock animation
> after a real unlock. Use the Debug "Show shape" menu or `-IsletDebugShape charge|low|volume|muted|
> brightness|unlock|full` to preview events.
