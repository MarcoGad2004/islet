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
- [ ] Read front app menu frames (Accessibility) and status-item bounds
- [ ] Wings vs chin decision, re-checked on app switch and menu changes; chin when no permission

## M4: Charging and battery
- [ ] Power source notifications; connected, full, low 20%/10%
- [ ] Wings and chin views, bolt pop, timings

## M5: Volume and brightness
- [ ] Catch volume, mute and brightness keys, apply the change, suppress the system display
- [ ] Chin HUD with the 16-step bar; mute state
- [ ] Expanded Display and Sound page with battery block, sliders, output picker

## M6: Media
- [ ] Now playing source (see RESEARCH.md §Now playing)
- [ ] Wings and chin views, level bars, pause state, hide after 30 s
- [ ] Expanded media page with controls and scrubber
- [ ] Swipe up to hide media; swipe down to bring it back; green dot hint

## M7: Unlock animation
- [ ] Listen for screen unlock; play the lock-opens sequence in wings or chin

## M8: Face unlock (M2 passed except Q13: the scan has no visuals over the lock screen)
- [x] Settings: enrol face (after Touch ID/password), store login password in the Keychain (island enrolment animation, test recognition and threshold slider included)
- [ ] On lock: scan, match, type password; 3 tries
- [ ] Face scan animation (looking, match, no match)

## M9: Polish
- [ ] Settings window, launch at login, permission prompts and status
- [ ] Priority and hand-back between events
- [ ] Tune springs and timings on the real display
