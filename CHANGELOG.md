# Islet release notes

Newest first. `scripts/release.sh <version>` publishes the section for that version as the GitHub release notes, so add
the section before releasing. Ideas and bugs found while testing go into the next version.

## 1.3.0 (unreleased)

- Glass look: like Siri's island on the iPhone, the island stays black and a strip along its bottom edge fades into
  glass, the desktop showing through blurred, with a light rim and a soft coloured glow. The panel's tiles and buttons
  are glass too. Turn it off in Settings → General → "Glass look".
- Cleaner Wi-Fi, Bluetooth, Screen Mirroring and Sound pages: no grey box, the page sits straight on the island, with
  Control Center style rows that light up under the pointer and the one in use on a glass pill.
- The notch answers the pointer whatever it is showing: hover over the wings, the wide bar or the chin and it swells a
  little with a springy bubble, then settles back when you move away. It reacts straight away, even in the middle of
  an animation (wings springing out, the chin dropping), instead of waiting for it to finish. What it shows grows with it, so the spacing stays even.

## 1.2.3 (2026-11-19)

- Islet checks for updates on its own: about a minute after it opens, then every 6 hours (and again after the Mac
  wakes if that long has passed). When a new version is out, a blue **Update** pill appears next to the battery in
  the panel; click it and the update plays out in the notch, progress bar, restart and all. It never installs
  without that click. Turn it off in Settings → Updates → "Check for updates automatically".

## 1.2.2 (2026-11-19)

- Updates no longer need the GitHub CLI or a GitHub account: Settings → Updates reads the latest release straight from
  GitHub and downloads it. It still runs only when you click Check for updates, and installs the update only if it is
  signed by the same developer as the copy you have.
- Updating plays out in the notch without a break, with one progress bar for the whole job: downloading (with the
  real percentage), verifying, installing and restarting. When it's done the bar turns green and draws itself into a
  check. The island stays on screen through the restart. The new version is put in
  place and opened while the old one is still showing "Restarting Islet…"; it takes over the island in the same
  shape, the old one quits, and the island carries straight on into "Updated to …" with a What's new button (click
  it for the release notes in their own window). The wide bar is used when the menu bar has room, the chin
  otherwise. If the new version doesn't start, the old one is put back and keeps running. Settings → Updates also
  has a Release notes button before you install.
- The chin (the bar under the notch used when the menu bar has no room) has the same 16 pt rounding on all four
  corners, instead of tighter corners at the top.

## 1.2.1 (2026-11-19)

- Macs without a notch: the drop that hangs from the top edge when you hover under the camera is now shaped like the
  notch, square at the top and flaring into the edge with rounded corners only at the bottom, instead of a pill that
  didn't quite meet the bezel.
- Keyboard brightness: the Display page of the panel has a keyboard backlight slider under the screen's
  (on Macs with a backlit keyboard), and the keyboard backlight keys, on Macs that have them, show the level in the
  island like screen brightness instead of the system's display.
- Focus: the icon next to the battery chip and the "on" notice now use the Focus's own colour and symbol from System
  Settings (orange for School, and so on), not always purple. A Focus turned on by its schedule now shows too; before,
  only one turned on by hand did. When two are on, the most recent one shows.

## 1.2 (2026-11-19)

**Macs without a notch**
- Islet now runs on MacBooks without a notch, and with the lid closed on an external display. Setup has a new step,
  **Your Mac**, which also lives in Settings → General. It asks whether this Mac has a notch (it starts on what macOS
  reports) and what to do without one:
  - **Bubble from the top edge** (the default): notices drip out of the top edge under the camera like a drop of
    liquid, come loose and float just below the menu bar, then rise back into the edge. Volume, brightness, charging,
    connection notices, Wi-Fi join progress, the face scan and the unlock animation all show this way. Music and the
    lock-screen padlock don't stay on screen, since a floating card can't sit there all the time.
    - Hover the middle of the menu bar, under the camera: a drop hangs down from the edge with an arrow at its tip.
      Swipe down with two fingers (or click it) and it lets go and bubbles out into the panel, music player included.
      Swipe up, click away or press Esc to close it.
  - **Drop down from the menu bar icon**: click Islet's menu bar icon and the panel drops down under it; right-click
    (or Control-click) for the menu. Notices grow out of the menu bar under the icon.
  - **Off**: no island at all, for using Islet just for face unlock.
- Choosing "No notch" on a notched Mac uses the no-notch style there too.
- Without an island in the notch or at the top edge, the menu bar icon always shows, since it's the way to Settings.

**Face unlock**
- New "Prove it's live" setting: **Random** (the default) asks for a blink, a smile, or a head turn left or right,
  picked at random for each attempt, once your face matches. The scan says which ("Smile to unlock", "Turn your head
  left"...) and gives 8 s to do it; a recorded video is unlikely to do the right thing in time. **Blink** keeps the
  old behaviour, **Off** matches the face only. Turning blink off before carries over as Off.
- Settings → Test recognition ticks Blink, Smile, Left and Right as each is seen, to check they work on your face.

**Wi-Fi**
- Networks that sign in with a username and password (WPA/WPA2/WPA3 Enterprise, as at work or university) now ask for
  both, marked with a person-and-key icon instead of a padlock.
- The connected network is always at the top of the list, with a **Disconnect** button. (Turning auto-join on or
  off for a network isn't possible: macOS only lets its own apps change that, so use Wi-Fi Settings.)
- Saved networks join straight away with what macOS stored, asking for the password only if that fails.
- Phones offering Instant Hotspot (your iPhone, or family members') are listed even when they aren't broadcasting,
  like Wi-Fi Settings' "Personal Hotspots": hotspot icon, cellular bars and a battery icon (phones only report
  their battery in quarters, so there's no percentage). Tap one and the phone turns its
  hotspot on, hands over the network's password, and the Mac joins it.
- A phone's Personal Hotspot is shown as one: the tile says "Hotspot" with the hotspot icon, the detail says
  "Personal Hotspot · <name>" and tags the network in green. Hotspots in the network list get the hotspot icon
  instead of the Wi-Fi one.
- Joining a Personal Hotspot (including when the Mac does it by itself) shows in the notch like volume does: the
  wide bar with the hotspot icon and cellular bars, and the phone's name under it (the chin when the menu bar is full).
- Joining a network or hotspot from the panel shows live progress if you close the panel before it finishes: the
  wide bar (or the chin) with the network's icon breathing and a spinner, the step underneath ("Asking Marco's
  iPhone…", "Joining…"), then a green check and "Connected to …", or a red cross and what went wrong.
- Connection notices (Wi-Fi, hotspot, Bluetooth, Focus) are passive: they don't show while the panel is open or in
  the few seconds after it closes, and joining a network from the panel never shows one.

**Notch motion**
- The wings (charging, media, events) close more smoothly: they pull in to a pill just bigger than the notch and
  ease down into it, like the chin does, and the icon and text draw in toward the notch as they fade instead of
  vanishing while the shape is still moving.

**Controls**
- After opening a tile's detail and going back, the tile kept its icon and text but lost its grey card. Fixed.

## 1.1.3 (2026-11-19)

**Face unlock**
- Locking with the power button (or Ctrl-Cmd-Q, or Apple menu → Lock Screen) no longer unlocks straight back. The
  scan waits for **Command+Shift**: the island shows "⌘⇧" beside the padlock and now and then spells out "Press ⌘ + ⇧
  to use Face Unlock". Opening the lid, or waking the display after it went to sleep, still scans by itself.
- Command+Shift also starts a fresh scan after one gave up, any time the Mac is locked.
- With no face in front of the camera for 10 s, the scan says "No face in view" and stops, instead of looking for a
  full minute.
- After the screen saver, the scan starts once it is dismissed, not while it is still showing.

## 1.1.2 (2026-11-19)

**Notch motion**
- Closing works like the iPhone's island: the chin or the expanded panel folds into a pill a little bigger than the
  notch, its corners staying round the whole way, then the pill eases down into the notch.
- Hovering over the notch while the chin grows out of it or folds back in no longer restarts the motion halfway: the
  shape keeps going, and a part that is already moving turns toward its new size with its momentum instead of pausing.

**Wide bar vs chin**
- With Islet's own Settings (or setup) in front, the menu bar check always failed and fell back to the chin. It now
  measures Islet's menus directly, so the wide bar is used whenever there is room, the same as in any other app.

## 1.1.1 (2026-11-19)

**Face unlock**
- Photo protection: a face has to blink before it unlocks (Settings, on by default), and a face inside the edge of a
  held-up photo, phone or tablet is refused. The scan shows "Blink to unlock" while it waits.
- Learns from successful unlocks: a live unlock that matched your original scan well is kept as an extra look (up to 24),
  so new light, glasses or a haircut are recognized. "Forget learned looks" is in Settings; scanning again resets them.
- In a dark room the screen eases brighter to light your face during the scan, then eases back.
- Test recognition shows whether a blink was seen, a photo edge, and the light level.

**Volume and brightness**
- The bar glides between levels on a spring, and the number rolls up or down. The Control Center sliders and their
  percentages animate the same way when you press the keys.

## 1.1 (2026-11-19)

**Control Center in the notch**
- The expanded notch is now a Control Center page: Wi-Fi, Bluetooth, AirDrop and Screen Mirroring tiles, a battery chip,
  a read-only Focus icon, and condensed brightness and volume sliders.
- Tap a tile's round icon to switch it, or the rest of the tile to open it. Wi-Fi lists and joins networks (secured ones
  ask for the password), Bluetooth lists the headphones, speakers, keyboards, mice and controllers you connect on purpose,
  Mirroring lists nearby iPads for Sidecar, AirDrop shows its mode and opens Finder's AirDrop window.
- Tap a slider to open its page: Display (brightness, Dark Mode, Night Shift, True Tone) and Sound (volume, output devices).
- Pages glide: sliders, tiles and the media name and artwork move to their new place on a spring, and the notch bubbles to
  its new size (Wi-Fi and Bluetooth get a taller panel).
- The Now Playing page matches the rest and has a back arrow to the controls.

**New island animations**
- Focus on and off, Wi-Fi connected and a Bluetooth accessory connected animate like charging: a wide notch when the menu
  bar has room, the chin otherwise.
- Volume and brightness use the wide notch (icon, number, 16-step bar below) when it fits. Option + Shift with the keys
  adjusts in quarter steps.
- The right side of the media wing shows the playing app's icon instead of the level bars.

**App**
- New app icon and a first-run setup: permissions (Accessibility, Camera, Location, Full Disk Access), optional face
  unlock, and a tip to hide the system Control Center icon. "Run setup again" is in Settings.
- Settings gear in the expanded notch; the menu bar icon can be hidden (Settings). Fixed a crash when hiding it.
- Settings > Updates checks the latest GitHub release (needs the GitHub CLI) and installs it.
- The lock stays put when the face scan starts, and the lock-screen bar has equal padding around the lock and check.

**Known gaps**
- System banners for Bluetooth and Focus are not hidden; turn them off in System Settings if you want only the island.
- Joining a secured Wi-Fi network with a password, connecting a Sidecar iPad, and the AirPlay display list are untested or
  unavailable. TVs and AirPlay displays open Display Settings.
- Full Disk Access is needed to see the active Focus; restart Islet after allowing it.

## 1.0 (2026-11-18)

First release: the notch as a dynamic island with now playing, charging and battery events, volume and brightness HUD
(16 steps), face unlock for the lock screen with the face-enrolment and scan animations, the unlock animation, and a DMG
installer.
