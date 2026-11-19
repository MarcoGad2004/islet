# Open technical questions (verify before building)

Things to confirm on this MacBook Pro (macOS 27) and against Apple docs, not settled facts. Record
what you find under each item.

## Notch and window

1. **Notch size**: confirm `safeAreaInsets.top` and the auxiliary top areas give the exact notch
   rectangle on the 14" display; check what happens with the lid closed and an external display.
2. **Window level and Spaces**: which level and `collectionBehavior` keep the panel above the menu
   bar, on every Space and over full-screen apps, without taking focus.
3. **Click-through**: best way to pass clicks outside the island shape to the menu bar below
   (`ignoresMouseEvents` toggled by pointer position vs. a custom hit test).
4. **Swipes**: confirm a non-activating panel receives two-finger `scrollWheel` events while the
   pointer is over it and another app is frontmost.

## Menu bar width check

5. Read the frontmost app's menu bar item frames through Accessibility (`AXMenuBar` children,
   `AXFrame`). Confirm it works for most apps and how quickly it updates on app switch.
6. Read status-item positions from the window list without Screen Recording permission (window
   bounds only).

## Now playing

7. The system now-playing API (MediaRemote) is private, and reports say macOS 15.4+ blocks it for
   third-party apps. Check what works on macOS 27: MediaRemote directly; community workarounds that
   go through an Apple-signed helper; or per-app scripting (Music, Spotify) as a fallback. Pick one
   and note its limits (which apps, artwork, scrubbing).

## Volume and brightness

8. Catch volume, mute and brightness keys with an event tap, consume them so the system display
   doesn't show, and apply the change ourselves. Which permission does the tap need (Accessibility
   vs Input Monitoring)?
9. Setting volume: CoreAudio on the default output device. Setting built-in display brightness has
   no public API (DisplayServices is private): confirm what works.

## Face unlock (spike in M2)

The owner accepts that this is weaker than Touch ID and is for convenience only. The plan is:
match the face with the camera, then type the login password (stored in the Keychain) into the
lock screen. Each question below can block it:

10. **Running while locked**: does the app keep running and get the lock notification right away?
11. **Camera while locked**: can the app capture camera frames while the lock screen is showing?
12. **Typing into the lock screen**: can posted keyboard events (`CGEvent`) reach the lock screen's
    password field, or does secure input block them? Is there any other supported route?
13. **Drawing over the lock screen**: can the island window appear above the lock screen so the
    face scan animation is visible? If not, the scan runs without visuals and only the unlock
    animation plays after unlocking.
14. **Face matching**: Vision detects faces and landmarks but has no "is this the same person" API.
    Options: a Core ML face-embedding model (check its licence) compared against the enrolled
    embedding; or Vision feature prints on the aligned face crop (likely weaker). Add a simple
    liveness check (e.g. a blink via eye landmarks) to resist a photo.
15. **Keychain**: store the password as a generic password item only this app can read; never log it.

If 11 or 12 can't be solved, drop face unlock from v1; the unlock animation still ships.

## Findings (M3 to M6)

- **5/6 Width check**: front app menus via Accessibility (`AXMenuBar` children, position + size); status
  items via `CGWindowListCopyWindowInfo` windows at layer 25 on the notch screen, bounds only, no Screen
  Recording needed. Re-checked on app switch, Space change, display change and when an event starts.
- **7 Now playing**: MediaRemote called directly returns nothing on macOS 27. The vendored
  mediaremote-adapter (BSD-3, pinned commit 14eed93, `vendor/`) works: Apple's `/usr/bin/perl` loads our
  helper framework. Works for any app (it picked up a browser video). Controls and seek go through the
  same script. A future macOS update could break it; fallback would be Music/Spotify scripting.
- **8 Volume keys**: `CGEvent` tap on NX system-defined events (subtype 8), consumed so the system HUD
  doesn't show. Needs Accessibility (the tap fails without it; Settings shows its status). Outputs without
  software volume pass through to the system.
- **9 Volume and brightness**: CoreAudio `VirtualMainVolume` and mute on the default output device.
  Brightness uses private DisplayServices (`DisplayServicesGet/SetBrightness`), which works for the
  built-in display.

## Control Center page (v1.1 spike)
Read-only probes run on the owner's Mac (macOS 27.2.1, 2026-11-19, `ControlSpike`, debug launch arg `-IsletDebugShape spike`).
Writes (toggling, joining, connecting) are not yet tested; they change the user's settings and need the owner's OK.
- **Q16 Wi-Fi: reads work.** After the Location prompt (granted), CoreWLAN returned the connected SSID and RSSI, a scan of
  16 networks all with names (13 secured), and 151 known networks. Writes untested: `setPower` (drops the connection,
  may want admin), `associate` (secured networks need a password; known ones may join from the keychain).
- **Q17 Bluetooth: reads work, power private symbols present.** `IOBluetoothDevice.pairedDevices()` listed 7 devices with
  connected state and no extra prompt; CBManager authorization stayed "not determined" so IOBluetooth is not gated by it.
  `IOBluetoothPreferenceGet/SetControllerPowerState` both resolve (read returned 1). Connect/disconnect and power set untested.
- **Q18 Focus: reading the DB needs Full Disk Access.** `~/Library/DoNotDisturb/DB/*.json` were not readable (permission
  denied). `shortcuts list` works (8 shortcuts, none is a plain Set Focus one). So: read state would need Full Disk Access
  (heavy ask) or another source; set works only through a shortcut the user creates or the app installs.
- **Q19 AirDrop: mode is readable.** `defaults read com.apple.sharingd DiscoverableMode` returned "Contacts Only". Whether
  writing it takes effect on this macOS is untested; `airdrop://` has no handler, so "open AirDrop" needs another route.
- **Q20 Mirroring:** one display, built in. No public AirPlay target list; the plan stays "open the system picker" unless a
  private route is found.
- **Q21 Display toggles: all present.** CoreBrightness loads. `CBBlueLightClient` status call works (Night Shift active=1,
  enabled=0) and has `setEnabled:`/`setActive:`. `CBTrueToneClient` has supported/available/enabled (all true) and
  `setEnabled:`. `KeyboardBrightnessClient` exists. Dark Mode reads via `AppleInterfaceStyle` and via System Events (Automation
  prompt granted); setting is untested.
- **Write probes (same Mac, each change reverted, `-IsletDebugShape spikewrites`):**
  - Dark Mode via System Events `set dark mode`: works, read back immediately, reverted cleanly.
  - Night Shift `CBBlueLightClient setActive:`: works (active 1 to 0 and back). `enabled` (the schedule) was not touched.
  - True Tone `CBTrueToneClient setEnabled:`: works and reads back.
  - AirDrop `defaults write com.apple.sharingd DiscoverableMode`: the value writes and reads back, but whether sharingd
    applies it live is not visible from here; check in the AirDrop window during the build, with the Settings-pane
    fallback if it is ignored.
  - Still untested (disruptive): Wi-Fi power/associate, Bluetooth connect/power, Focus via shortcut, mirroring.
- **Q22 System banners (desk research, not tested).** No API lets an app suppress another process's notification or the
  AirPods connect card. AirPods popups come from the auto-switching feature; the workable fix is per device, in Bluetooth
  settings: Options > "Connect to this Mac" > "When last connected to this Mac"
  (discussions.apple.com/thread/254640801, support.airbuddy.app). Nothing found for the Focus banner; check System Settings >
  Notifications and Focus on this Mac. Plan: show the island animation and tell the owner which system toggles remove the duplicate.
- **Q23 Event sources: verified on this Mac (2026-11-19, `-IsletDebugShape spikewatch`, Full Disk Access granted).**
  - **Focus works.** With Full Disk Access, `~/Library/DoNotDisturb/DB/Assertions.json` is readable (11 KB). Watching the DB
    folder with a `DispatchSource` file-system source fired within a second of toggling. Turning Do Not Disturb on parsed as
    `data[0].storeAssertionRecords[].assertionDetails.assertionDetailsModeIdentifier` resolved to the name through
    `ModeConfigurations.json` (`data[0].modeConfigurations[id].mode.name`), giving "Do Not Disturb". Off leaves no assertion
    records. One change writes the file about five times: debounce ~0.3 s and compare to the previous mode.
  - **Wi-Fi works.** `CWWiFiClient` delegate events `ssidDidChange`, `linkDidChange` and `powerDidChange` all registered
    and fired for each network switch (the SSID passes through nil, then the new name), each event two or three times.
    Debounce ~1 s, ignore nil, announce only when the SSID differs from the last announced one.
  - **Bluetooth works with filtering.** `IOBluetoothDevice.register(forConnectNotifications:)` fires on the device's own
    background queue (not the main thread; touching main-actor state there crashed the first probe). It also fires at
    registration for already-connected devices, for unnamed nearby devices (name nil, never connected), for attempts that
    drop (Bedroom: isConnected true, then false 1.5 s later; iPad Pro likewise), and three times for AirPods (names
    "Marco's AirPods Pro" x2 and "AirPods Pro"). Rule: wait ~1.5 s, require a name and `isConnected` still true,
    dedupe by address, skip devices connected at launch. The disconnect callback is reliable (registered per device).
- **Q16-Q17 write tests (2026-11-19, `spikeactive`, `spikebt`; everything put back):**
  - Wi-Fi `setPower(false/true)`: works, no admin prompt; reconnected to the same network within seconds.
  - Wi-Fi `associate(to:password: nil)`: **fails with -3900 "tmpErr"** even when rejoining the current secured network, and
    `networksetup -setairportnetwork` fails the same way. So a known secured network cannot be joined without a password
    (the saved one needs a Keychain prompt). Joining plan: open networks directly; secured ones ask for the password in
    the notch and call `associate(to:password:)` (untested: needs a real password, which the spike never handles);
    always offer "Wi-Fi Settings" as the fallback. Note `networksetup -getairportnetwork` wrongly says "not associated"
    on this macOS; use CoreWLAN for the SSID.
  - Bluetooth power via `IOBluetoothPreferenceSetControllerPowerState`: works (1 to 0 to 1, no prompt).
  - Bluetooth `closeConnection()` disconnected the AirPods; `openConnection()` returned 0 and connected them (the first
    attempt, 3 s after a disconnect, did not connect within 10 s, the second did). Treat connect as asynchronous: show
    "Connecting..." and poll `isConnected` for ~20 s. The paired-device name changed from "Marco's AirPods Pro" to
    "AirPods Pro" and back, so key devices by address.
  - Still untested: AirDrop mode taking effect live, mirroring, Wi-Fi join with a password.
Sources: developer.apple.com/forums/thread/769950, developer.apple.com/documentation/corewlan/cwinterface/setpower(_:),
github.com/toy/blueutil, talk.automators.fm/t/get-current-focus-mode-via-script/12423,
developer.apple.com/documentation/corewlan/cweventdelegate, developer.apple.com/forums/thread/738748.

## Distribution

16. Personal use only. `scripts/make-dmg.sh` makes a DMG signed with the Apple Development certificate
    (`DEVELOPMENT_TEAM` in `project.yml`). Accessibility and camera grants are tied to the signature, so
    keep signing stable to avoid re-granting.

### M2 spike results (the harness was removed once it had answered Q10-Q13; see git history)


| Q  | Result |
|----|--------|
| 10 | **Yes.** `screenIsLocked` arrives immediately; the app keeps running. |
| 11 | **Yes.** ~30 fps camera frames while locked; Vision finds a face in every sampled frame. |
| 12 | **Yes (needs Accessibility).** Both `cghidEventTap` and `cgSessionEventTap` keystrokes reached the password field (6 of 6) even with secure input on. Fails silently if the app isn't trusted: signing must be stable (set `DEVELOPMENT_TEAM`). |
| 13 | First try failed (high window level, and a private space at a wrong level with no `canBecomeVisibleWithoutLogin`). Second try copies the SkyLightWindow library's recipe: window level `Int32.max - 2`, `canBecomeVisibleWithoutLogin = true`, private SkyLight space at absolute level 400 (NotificationCenterAtScreenLock), window added with mask 7. In `Support/SkyLightSpace.swift`. **Unverified while locked: needs a lock test.** |
| 14 | **Solved in principle:** AuraFace-v1 (Apache-2.0) Core ML, 112×112 aligned input, 512-d embedding, cosine score. The threshold (default 0.45) must be tuned with Settings → Test recognition, including on someone else's face. Liveness (blink) not built yet. |
| 15 | Done in `FaceStore`: generic-password Keychain items, never logged. |
