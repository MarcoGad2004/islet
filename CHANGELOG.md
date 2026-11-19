# Islet release notes

Newest first. `scripts/release.sh <version>` publishes the section for that version as the GitHub release notes, so add
the section before releasing. Ideas and bugs found while testing go into the next version.

## 1.1.4 (unreleased)

**Face unlock**
- New "Prove it's live" setting: **Random** (the default) asks for a blink, a smile, or a head turn left or right,
  picked at random for each attempt, once your face matches. The scan says which ("Smile to unlock", "Turn your head
  left"...) and gives 8 s to do it; a recorded video is unlikely to do the right thing in time. **Blink** keeps the
  old behaviour, **Off** matches the face only. Turning blink off before carries over as Off.
- Settings → Test recognition ticks Blink, Smile, Left and Right as each is seen, to check they work on your face.

**Wi-Fi**
- Networks that sign in with a username and password (WPA/WPA2/WPA3 Enterprise, as at work or university) now ask for
  both, marked with a person-and-key icon instead of a padlock.
- Saved networks join straight away with what macOS stored, asking for the password only if that fails.
- Phones offering Instant Hotspot (your iPhone, or family members') are listed even when they aren't broadcasting,
  like Wi-Fi Settings' "Personal Hotspots": hotspot icon, cellular bars and battery. Tap one and the phone turns its
  hotspot on and the Mac joins it.
- A phone's Personal Hotspot is shown as one: the tile says "Hotspot" with the hotspot icon, the detail says
  "Personal Hotspot · <name>" and tags the network in green. Hotspots in the network list get the hotspot icon
  instead of the Wi-Fi one.
- Joining a Personal Hotspot (including when the Mac does it by itself) shows in the notch like volume does: the
  wide bar with the hotspot icon and cellular bars, and the phone's name under it (the chin when the menu bar is full).
- Connection notices (Wi-Fi, hotspot, Bluetooth, Focus) are passive: they don't show while the panel is open or in
  the few seconds after it closes, and joining a network from the panel never shows one.

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
