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
- [x] On lock: scan, match, type password; 3 tries (needs a real lock test)
- [x] 1.1.1: blink liveness, photo/phone edge check, learning from live unlocks, dark-room brightness ramp (all need testing on the Mac)
- [x] 1.2: random liveness challenges (blink, smile, head turn), Enterprise Wi-Fi sign-in, Personal Hotspot status and notice (need testing on the Mac)
- [x] Face scan animation (looking, match, no match); visible over the lock screen only if the SkyLight space works (RESEARCH.md Q13)

## 1.2: Macs without a notch
- [x] "Your Mac" step in setup and Settings: notch or not, and the no-notch style (top edge bubble, menu bar icon, off)
- [x] Top edge bubble: drop from the edge, floating card, hover strip orb, two-finger swipe to the panel
- [ ] Try it with "No notch" on the notched Mac, then on a Mac without a notch

## 1.4: Notifications and calls
- [x] Spike (RESEARCH.md Q27-Q31): read banners, hide the system banner, calls
- [x] Notifications: banner watcher, hide the system banner, card, stacking, click / swipe, the taller card
- [x] FaceTime: ringing wings, in-call wings with the time, hover bar, call page (mute, camera, end); built but switched
      off (`AppDelegate.callsEnabled`): calls get their own design in a later update
- [x] Settings > General: show notifications in the notch, hide message text
- Preview: `-IsletDebugShape notification|notifications|ring|call`
- [x] Tried on the Mac (2026-11-20): one banner and two in a row reach the card, the corner stays empty, nothing comes back
      after the card times out
- [x] Wide bar / chin, stacking ("N more", the strip), the list page, the banner's buttons (DESIGN.md, revised
      2026-11-20). Tried: a burst of four from one app (macOS groups them as a `BannerStack`) reaches the chin with
      "3 more"
- [ ] Still to try: hover card, click to open, the list (swipe down, Clear all, rows), a real Duo Approve / Deny,
      opening Notification Center while Islet runs; does Close remove it from Notification Center's list?

## 1.5: Messages in the notch
- [x] Spike (RESEARCH.md Q32-Q38): read chat.db, decode attributedBody, contact names, watch the WAL, send via Messages
- [x] Conversation page from a Messages notification (click or Reply), live updates, reply field, Open in Messages
- [x] Lists in the panel scroll under two fingers; swipe up closes only when the list can't go further (DESIGN.md
      "Gestures"); the Wi-Fi, Bluetooth and notification lists too
- [x] Settings: "Open Messages conversations in the notch". Preview: `-IsletDebugShape conversation` (the chat with
      the "Islet test" message)
- [x] Tried: the conversation page opens with names, bubbles, times and "Delivered"
- [ ] Still to try: replying from the notch, a real incoming message opening its conversation, a group chat, SMS,
      the swipe rule on the trackpad, Esc while typing
- [x] Permission rows in setup and Settings for Contacts and controlling Messages (`MessagesAccess`)

## Later: calls
- [ ] Redo the call design with what Q30 found: the caller's name, Answer / Decline and iPhone calls from the banner
- [ ] Find out whether the banner has the caller while the first call rings (probe that re-reads it every 0.25 s)

## M9: Polish
- [x] Settings window, launch at login, permission prompts and status
- [x] Priority and hand-back between events
- [ ] Tune springs and timings on the real display

## M10: Control Center page (v1.1)
- [ ] Spike on this Mac (RESEARCH.md Q16-Q21): Wi-Fi scan/join (Location), Bluetooth connect and power, Focus read and
      set, AirDrop mode, mirroring, Night Shift / True Tone / Dark Mode. Record what works, per control.
- [ ] Layout: header battery chip + read-only Focus icon, four tiles (Wi-Fi, Bluetooth, AirDrop, Mirroring), two
      condensed sliders; tap vs drag; expand and back
- [ ] Display detail (brightness, Dark Mode, Night Shift, True Tone) and Sound detail (volume, output devices)
- [ ] Wi-Fi, Bluetooth, AirDrop, Mirroring tiles and their detail views, each with a Settings-pane fallback
- [ ] Event animations like charging: Focus on/off, Wi-Fi connected, Bluetooth device connected (RESEARCH.md Q22-Q23)
- [ ] Permissions in onboarding and Settings (Location, Bluetooth, Automation, Full Disk Access for reading Focus); how to hide the
      system Control Center icon
- [ ] Ship as v1.1 (`scripts/release.sh 1.1`)

## Distribution
- [x] `scripts/make-dmg.sh` builds a Release app and packs `dist/Islet.dmg` (see README).

> Built but not yet exercised on real hardware: the menu bar width check on varied apps, charger and
> low-battery events, volume/brightness keys, media controls and scrubbing, and the unlock animation
> after a real unlock. Use the Debug "Show shape" menu or `-IsletDebugShape charge|low|volume|muted|
> brightness|unlock|full` to preview events.
