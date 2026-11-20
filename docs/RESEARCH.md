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
    **1.2:** random challenges against a replayed video: after the match the scan asks for one of blink, smile
    (mouth corner-to-corner width, in eye distances, over 1.12× its narrowest recent value for 2 frames) or a head
    turn left/right (nose offset from the eye midpoint moves 0.18 eye distances from its first 3 frames, the asked
    way; raw camera x grows when you turn to your left). Random challenges only count after they are shown, and
    while one is up, non-matching frames don't count as misses (a turned face may not match); an 8 s limit ends
    the attempt instead, and the next attempt picks again. Thresholds unverified on real faces: Test recognition
    ticks each one.
15a. **Instant Hotspot** (1.2): phones offering their hotspot aren't in a CoreWLAN scan until they start
    broadcasting. Sharing.framework's private `SFRemoteHotspotSession` (`setDelegate:`, `startBrowsing`,
    `stopBrowsing`, `enableHotspotForDevice:withCompletionHandler:`) lists them from sharingd with no entitlement;
    the delegate gets `session:updatedFoundDevices:` with `SFRemoteHotspotDevice`s (`deviceName`,
    `deviceIdentifier`, `signalStrength` 0-4, `batteryLife` in 25% steps rounded up). The protocol's enable handler is
    `v@?@"SFRemoteHotspotInfo"@"NSError"`, but `-[SFRemoteHotspotSession enableHotspotForDevice:withCompletionHandler:]`
    wraps it and calls the caller's block with `(name, password, error)` (disassembly, macOS 27.2). It escapes. macOS does not join by itself: the caller associates with CoreWLAN, retrying
    while the phone starts broadcasting. Browsing verified on macOS 27.2; joining needs testing.
15b. **Wi-Fi auto-join** (1.2): not settable. CoreWiFi's private `CWFNetworkProfile.setAutoJoinDisabled:` +
    `CWFInterface updateKnownNetworkProfile:properties:error:` fail with Cocoa error 4097 (connection to
    `com.apple.private.corewifi-xpc` refused: Apple-only entitlement). CoreWLAN's public profile has no auto-join flag.
    Disconnect uses public `CWInterface.disassociate()`.
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
  `setEnabled:`. `KeyboardBrightnessClient` exists. It works from an app (2026-11-19): `copyKeyboardBacklightIDs`, `isKeyboardBuiltIn:`,
  `brightnessForKeyboard:` read the level (0.19, matching Control Center); writes use
  `setBrightness:fadeSpeed:commit:forKeyboard:`. Focus: `ModeConfigurations.json` modes carry `tintColorName`
  (an NSColor class method name); a Focus on by schedule has no assertion record, only a
  `DNDModeConfigurationScheduleTrigger` (weekday bit order assumed Sunday first, not yet checked). Dark Mode reads via `AppleInterfaceStyle` and via System Events (Automation
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

## Notifications and calls in the notch (1.4 spike)

Owner request (2026-11-20): show incoming notifications, and FaceTime / iPhone calls iPhone-style, in the notch, without
the system banner also appearing in the top-right corner. There is no public API: `CXCallObserver` isn't offered to
native macOS apps, and the only way LockDown Browser hides banners is Apple's exam-mode entitlement
(`com.apple.developer.automatic-assessment-configuration`, granted by Apple to assessment apps only), plus old code
that toggles Do Not Disturb.

27. **Can a banner be read?** Through Accessibility, which Islet already has.
28. **Can the system banner be hidden** so only the notch shows it?
29. **Can the notification store be read** instead (for banners turned off in Settings)?
30. **Incoming calls**: what does a FaceTime call and an iPhone call relayed to the Mac expose, and can Accept /
    Decline be pressed?
31. **Active calls**: can the call's state (who, how long, muted) be read from FaceTime / Phone?

**Results so far (owner's Mac, macOS 27.2, 2026-11-20; probe `axspy` kept out of the repo):**
- **Q27 yes, fully.** Each banner arrives in `NotificationCenter` (`com.apple.notificationcenterui`) as a new window
  (`AXWindow`, subrole `AXSystemDialog`, title "Notification Center"); an `AXObserver` gets `AXCreated` for it about
  0.5-0.6 s after the post. Inside is one `AXGroup` with subrole `AXNotificationCenterBanner` whose description is
  "App, Title, Subtitle, Body", with children `AXStaticText` identified `title`, `subtitle` and `body`, and actions
  `AXPress`, "Show Details", "Show" and "Close" (named actions, `Name:Close` etc.).
- **Q28 yes, with no flash.** Pressing "Close" from the observer callback lands 7-8 ms after `AXCreated`, but a faint
  ghost of the banner still shows for about 0.2-0.3 s while it fades in and out. Setting the window's `AXPosition` to
  (-3000, -3000) in the same callback (it is settable) and then closing it left no visible banner at all: 12 screen
  captures of the top-right corner across the post were identical to before. Only windows that contain an
  `AXNotificationCenterBanner` may be touched, so opening Notification Center itself is never affected. Open: whether
  "Close" also removes it from Notification Center's history (moving it away without closing may keep it there).
- **Q29 no (without Full Disk Access).** The store is `~/Library/Group Containers/group.com.apple.usernoted/db2/db`;
  listing the folder fails with "Operation not permitted" and SQLite gets "authorization denied". It would need Full
  Disk Access for Islet, and Apple has moved and locked it before, so reading banners (Q27/Q28) is the way.
- **Q30 (first try): the incoming-call banner is opaque.** A FaceTime call (and the relayed iPhone call) arrives as a
  banner window like any other, but its `AXNotificationCenterBanner` is identified `FACETIME_NOTIFICATION` with the
  description "FaceTime Notification" and no children: no caller, no Accept / Decline. Its content is drawn by
  another process. FaceTime itself isn't running while it rings. (The iPhone call went unanswered on the Mac: Phone
  showed "Do you want to upgrade to Wi-Fi calls on this Mac?" and logged it as missed.)
- **Q31 yes, for FaceTime.** Once answered, FaceTime's window (`SceneWindow`, title "FaceTime") exposes the other
  person's name as a button (`desc="Mom"`), `AvatarView` "Connecting…" until it connects, the camera and microphone
  as switches (`toggleVideoButton`, `toggleMicMenuButton`, value 1 = on) and the End button (`leaveButton`), all
  pressable. The default input device reports running (`kAudioDevicePropertyDeviceIsRunningSomewhere`) while the call
  is up. Phone's Recents list then has the call, e.g. "Mom, Incoming FaceTime Video, 1:21 PM".

**Second call test (2026-11-20, 13:51; an iPhone call answered on the Mac, then a FaceTime call that rang during it and
was answered with "End & Accept"):**
- **Hit-testing the banner finds nothing.** `AXUIElementCopyElementAtPosition` over the call banner's frame returns the
  app underneath (here Claude's window), so the banner's drawing isn't reachable that way.
- **But the banner does fill in later.** It is created empty (`FACETIME_NOTIFICATION`, no children), and on a later
  `AXLayoutChanged` it holds an `iOSContentGroup`:
  - **Ringing (FaceTime)**: `AvatarView` desc "FaceTime Audio", an element desc "Mom, FaceTime Video" (the name is wrapped in
    U+202A / U+202C direction marks), and two `AXPopUpButton`s identified `menuControlIdentifier`: "Answer" with named
    actions `Answer` and `Answer as Audio`, and "Decline" with `Decline`, `Remind Me in 1 Hour`, `Remind Me in 15 M…`.
    So Accept / Decline **can** be pressed from Islet.
  - **iPhone call in progress** (relayed through the Mac, Phone app open): the banner stays up as the call's controls:
    `AvatarView` "Phone", an element "Mom, 0:13" (name and time), and buttons "FaceTime Video", "Mute", "Keypad", "More",
    "End". So relayed iPhone calls can be shown and controlled from the banner, without the Phone window.
  - Not yet known: whether the content is there while the *first* call rings (no layout change came then, and the probe
    didn't re-read it). Next probe: re-read the banner every 0.25 s while it rings.
- **FaceTime's window in the call:** once connected `AvatarView` reads "￼ FaceTime Video" (U+FFFC first), not the name;
  the name is on the participant button (no identifier, named action "Take Live Photo"). The microphone reports "in use"
  for both calls. Answering FaceTime during a phone call shows FaceTime's "End Current Call?" sheet.

**Notifications on the Mac (2026-11-20, the built app):** a second banner posted while the first is up does not get a new
window: macOS adds it to the first one's window (already off screen), so `AXCreated` alone misses it. Islet also listens
for `AXLayoutChanged` and looks for new banner identifiers (a UUID each) in the windows it has moved. The banner window
spans the whole screen and also hosts the desktop widgets (moving it off screen left the widgets where they were), so
its size can't tell it from Notification Center opened by the user (see the next finding for what does). Not tried yet: opening Notification Center while Islet runs.

**Banners with their own buttons (2026-11-20, a Duo push from the iPhone):** the banner's named actions include the
app's buttons: `Show Details`, `Deny`, `Approve`, `Close` (Slack: `Remind Me Next Week`, …). On screen they sit behind an
Options menu. Pressing the named action should do what the menu item does (not tried yet: it would approve a real sign-in).
The banner also has `AXStaticText` id `header` ("TIME SENSITIVE") and its description ends ", from iPhone" for iPhone
notifications; Duo Mobile isn't on the Mac, so its icon can't be looked up by name. Alerts (the kind that stay) have
subrole `AXNotificationCenterAlert`, not `…Banner`, so Islet never takes them.
- **Notification Center opened by the user** arrives as a new window (`AXCreated`) holding the list: an
  `AXNotificationListItems` group with alerts, banners and stacks (`AXNotificationCenterBannerStack`, action
  `Clear All`) and a "Clear All" button. It can hold as few as two banners, so counting them doesn't tell it apart;
  those markers do, and Islet skips any new window that has one.
- **Several from one app close together** come as one `AXNotificationCenterBannerStack` in the banner window (texts are
  the newest one's, description ends ", stacked", actions `Show`, `Clear All`), so a stack is not a sign of the opened
  Notification Center. What marks that is its `AXNotificationListItems` group and its "Clear All" *button*.

## iMessage in the notch (1.5 spike)

Owner request (2026-11-20): see conversations and reply from the notch, with a mini Messages view when it's expanded.
Probe: `-IsletDebugShape messagesspike` (read only; logs counts and yes / no, never text, names or numbers) and
`messagessend` (one test message to the owner's own address), in `Spike/MessagesSpike.swift`, log
`~/Library/Logs/Islet-messages-spike.log`.

32. **Can the history be read?** Yes, with Full Disk Access (each copy of Islet needs its own entry; a copy without it
    gets SQLite error 23 "authorization denied"). `~/Library/Messages/chat.db` opens read-only: 744,119 messages and
    1,858 chats on the owner's Mac. `message` has `text`, `attributedBody`, `is_from_me`, `date` (ns since 2001),
    `handle_id`, `associated_message_type` (reactions / edits), `cache_has_attachments`, `thread_originator_guid`,
    `is_read`.
33. **Is the text there?** Of the latest 300: 32 have it only in `attributedBody` (a typedstream `NSAttributedString`),
    267 in both, 1 in neither (an attachment). `NSUnarchiver` decoded all 299 bodies; where both exist they matched in
    264 of 267 (the rest are edits or mentions). 18 were reactions / edits, 40 had attachments.
34. **Which conversations?** The latest 20 chats: 17 one-to-one, 3 groups (all named); services iMessage 11, RCS 5,
    SMS 4, so iPhone texts come through as well.
35. **Names?** With Contacts allowed (`NSContactsUsageDescription` added), 17 of the 22 people in those chats match a
    contact, comparing the last 10 digits of numbers and lower-cased emails over one pass of all 442 contacts (the
    phone-number predicate only matched 1: Messages stores "+1…", contacts as typed).
36. **New messages without polling?** `chat.db-wal` changes as messages arrive, so a file watch can trigger a read.
37. **Sending?** Yes, through Messages (Apple Events, `com.apple.security.automation.apple-events` already on; the
    owner allowed Islet to control Messages): `send "…" to participant "<address>" of (1st account whose service type =
    iMessage)` returned in 88 ms, and the row appeared in `chat.db` sent at once and delivered within 1 s (one test
    message to the owner's own address, with their OK). Islet itself makes no network connection: Messages sends it.
    Not tried: SMS / RCS (would be `service type = SMS`), a group chat (`send … to chat id "…"`), attachments.
    `get service type of every account` fails with -10000; the `1st account whose …` form works.
38. **The banner's own Reply?** No: a Messages banner's actions are `Show Details`, `Mark as Read`, `Show More`, `Close`,
    with no text field, so a reply goes through Messages (Q37). "Show More" only expands the system banner, so Islet's
    card leaves it out; "Mark as Read" stays.

**Verdict:** the mini Messages view is feasible: read the conversation from `chat.db` (watched through its `-wal`), names
from Contacts, replies through Messages. Needs Full Disk Access, Contacts and Automation (Messages). Private formats
(`chat.db`'s schema, `attributedBody`) can change with macOS, like the media adapter.

