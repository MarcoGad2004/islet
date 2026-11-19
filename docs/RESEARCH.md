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
    **1.1.1:** two checks built, both for a plain 2D webcam (no depth or IR, so neither is Face ID grade):
    a blink (eye height over width along the eye axis drops below 60% of its recent open level, then
    recovers above 82%), and a rectangle check (Vision `VNDetectRectanglesRequest` finds a quad that
    snugly encloses the face: a print, phone or tablet edge; 4 of the last 10 frames). A video of the
    owner blinking on a screen held so its edges are out of frame could still pass. Unverified: how far
    Vision's eye contour actually closes on a blink; Settings → Test recognition shows "Blink seen" to
    check it. Learning keeps up to 24 extra embeddings from live unlocks that score ≥ threshold + 0.08
    against the original enrolment (not against learned ones, so it can't drift) and aren't near-duplicates
    (cosine < 0.92). It helps recognition in new conditions; false positives are held back by the anchor
    rule, the liveness checks and the threshold, not by learning itself.
    **1.1.4:** random challenges against a replayed video: after the match the scan asks for one of blink, smile
    (mouth corner-to-corner width, in eye distances, over 1.12× its narrowest recent value for 2 frames) or a head
    turn left/right (nose offset from the eye midpoint moves 0.18 eye distances from its first 3 frames, the asked
    way; raw camera x grows when you turn to your left). Random challenges only count after they are shown, and
    while one is up, non-matching frames don't count as misses (a turned face may not match); an 8 s limit ends
    the attempt instead, and the next attempt picks again. Thresholds unverified on real faces: Test recognition
    ticks each one.
15a. **Instant Hotspot** (1.1.4): phones offering their hotspot aren't in a CoreWLAN scan until they start
    broadcasting. Sharing.framework's private `SFRemoteHotspotSession` (`setDelegate:`, `startBrowsing`,
    `stopBrowsing`, `enableHotspotForDevice:withCompletionHandler:`) lists them from sharingd with no entitlement;
    the delegate gets `session:updatedFoundDevices:` with `SFRemoteHotspotDevice`s (`deviceName`,
    `deviceIdentifier`, `signalStrength` 0-4, `batteryLife` in 25% steps rounded up). The enable handler is
    `v@?@"SFRemoteHotspotInfo"@"NSError"` (from the protocol's extended type encoding) and escapes; the info has
    `name`, `password`, `channel`. macOS does not join by itself: the caller associates with CoreWLAN, retrying
    while the phone starts broadcasting. Browsing verified on macOS 27.2; joining needs testing.
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
  - **AirDrop mode (verified):** `defaults write com.apple.sharingd DiscoverableMode` alone changes only the stored value;
    the Mac's real setting did not change until `killall sharingd` (launchd restarts it). With the restart, Finder's AirDrop
    window showed "No One" for Off and "Contacts Only" after restoring. `SFAirDropDiscoveryController` (Sharing.framework)
    exists but read mode 0 from a command-line process and did nothing, so not used.
  - Decision (owner, 2026-11-19): the AirDrop tile is read-only and opens Finder's AirDrop window; restarting sharingd
    from a tile is too disruptive.
  - Bluetooth class of device is only reliable for AirPods (major 4); phones, tablets, the watch and the HomePod report
    0, so the accessory filter uses class and name. A full Wi-Fi scan takes about 8 s, so the list shows
    `cachedScanResults()` first.
  - Sidecar: `SidecarCore.framework` (private) loads from an app; `SidecarDisplayManager.sharedManager` lists "Marco's iPad
    Pro" in `devices`, with `connectToDevice:completion:` and `disconnectFromDevice:completion:`. Listing verified;
    connecting not yet tried. AirPlay targets (Roku) are not in this list.
  - Still untested: Sidecar connect, Wi-Fi join with a password.
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

## Lock-screen trigger (1.1.3 spike)

Locking with the display on (power button, Ctrl-Cmd-Q, Apple menu) should wait for Command+Shift before scanning;
any display sleep resets that so the next wake scans on its own. Probe: `Spike/LockInputSpike.swift` (debug builds,
logs to `~/Library/Logs/Islet-lock-spike.log`).

24. **Command+Shift on the lock screen**: which of these sees it while locked: polling
    `CGEventSource.flagsState` (HID or session), a global `flagsChanged` monitor, a listen-only session tap?
25. **Click on the island while locked**: does the panel (SkyLight lock-screen space) receive a click once it
    stops ignoring the mouse? Fallback trigger if Q24 fails.
26. **Event order**: on lid open and on waking a locked display, does `screenIsLocked` arrive before or after
    `screensDidWake`? If after, a lock within ~2 s of a wake counts as a wake.

**Results (owner's Mac, macOS 27.2.1, 2026-11-19; the probe was removed afterwards):**
- **Q24 yes, all three.** While locked, a global `flagsChanged` monitor, a listen-only session tap and polling
  `CGEventSource.flagsState(.hidSystemState)` all saw ⌘, ⇧⌘ and ⇧ within ~50 ms, with the display on and after
  a wake. Secure input on the password field does not hide modifier changes. Built on the global monitor.
- **Q25 yes.** A click on the island while locked reached the panel (once it stopped ignoring the mouse). Not
  used, kept as a fallback.
- **Q26 lock comes after sleep, so no workaround.** Lid close: `willSleep`, `screensDidSleep`, then
  `screenIsLocked` (display already off). Lid open: `screensDidWake`, `didWake`, still locked. Power button:
  `screenIsLocked` with the display on, `screensDidSleep` ~5 s later. Ctrl-Cmd-Q: `screenIsLocked` with the
  display on, then the release of ⌃ and ⌘ arrives (never ⇧⌘ on its own, so it can't start a scan by mistake).
