# Islet release notes

Newest first. `scripts/release.sh <version>` publishes the section for that version as the GitHub release notes, so add
the section before releasing. Ideas and bugs found while testing go into the next version.

## 1.1.2 (unreleased)

**Notch motion**
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
