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

### Extended brightness (1.7, 2026-11-24)

`ExtendedBrightness` uses BrightIntosh's gamma technique: a 1 x 1 pt window (shielding level + 1, top-left corner)
shows an rgba16Float EDR pixel at 1.7 in extended linear sRGB, so the display enters EDR mode, then
`CGSetDisplayTransferByTable` writes the captured table times the factor (1 + extra, ≤ 1.6), eased over 0.25 s.
`CGDisplayRestoreColorSyncSettings` undoes it; macOS also restores the table when the app exits. On this Mac
(Mac16,8, macOS 27.2) headroom read 4.0 at full brightness within ~1.1 s of the pixel showing (potential 16), and
`CGSetDisplayTransferByTable` accepts the scaled table, but **`CGGetDisplayTransferByTable` reads entries back
clamped at 1.0**, so the once-a-second integrity check compares an entry at a quarter of the ramp, which stays under 1.0
scaled. `didChangeScreenParameters` also fires on EDR headroom changes, so only a lost built-in display ends it there.
**Unverified:** that the desktop actually gets brighter (screenshots don't show the table; check by eye), and that
Night Shift and True Tone come back cleanly after the restore.

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
    **Next (2026-11-22, owner request: more security without asking the user to move):**
    - *Camera pin:* `FaceCamera.builtIn()` takes only `.builtInWideAngleCamera`, not `isContinuityCamera`, made by
      "Apple Inc.". The owner's Mac lists "MacBook Pro Camera" and "iPhone Duo Camera"; `default(for: .video)` could
      have picked either, and a virtual camera could inject video.
    - *Spoof model:* Minivision Silent-Face-Anti-Spoofing (Apache-2.0), MiniFASNetV2 at a 2.7x face crop plus
      MiniFASNetV1SE at 4.0x, 80x80 BGR 0-255, mean softmax class 1 = real. Converted to one Core ML model by
      `scripts/convert-antispoof.py` (3.5 MB, committed). Core ML output equals PyTorch to 4 decimals on the repo's
      samples; through the Swift path (Vision box, our crop) the samples score fake 0.05 / 0.02, real 0.98. Its
      training crops came from a RetinaFace box; ours from Vision's, which is close but not identical. Thresholds
      (live ≥ 0.75, refuse < 0.25 over 6+ frames) are guesses. **Unverified on this Mac's camera**, especially in a
      dim room, where such models tend to call real faces fake: Test recognition shows its score.
    - *Light check (`FacePulse`):* the display brightness swells once by 0.3. Face patches (forehead, nose, chin,
      cheeks, both sides) and the top frame corners are read in linear light; each patch's change is divided by the
      background's, so auto-exposure cancels (exposure and white balance are also locked when the camera allows).
      `contrast` = centre change (needs ≥ 0.05), `shape` = (centre − sides) / centre (needs ≥ 0.15; a flat print is
      ~0), and once 8 passing unlocks are learned, the profile must correlate ≥ 0.7 with the learned mean (a face
      turned slightly still correlates ~0.9 in the model). It only ever vouches or doesn't; it never refuses. **All
      thresholds unverified on real faces; whether `pulseForFaceScan` works on the lock screen is unverified too**
      (the dark-room boost suggests DisplayServices does). Test recognition → Check Light shows depth and shape.
    - *Adaptive threshold:* scores are each confirmed unlock's median frame score (not the first matching frame,
      which would only ever be above the threshold and ratchet it up), plus the best score of a miss followed by a
      password unlock within 60 s. Threshold = 5th percentile − 0.05, clamped to [slider, slider + 0.15] (since 1.6 there is no slider: the Security level sets the floor, margin and raise).
    - *Direct sun (2026-11-23, owner report: in direct sunlight it struggled to tell a real face from a photo):* the
      screen's light (~100-200 lux at the face) is lost in sunlight (10,000+ lux), so the pulse can't respond, and
      harsh light is where texture models misjudge real faces. macOS doesn't expose the camera's exposure time or ISO
      (iOS-only on `AVCaptureDevice`), so a bright room can't be read directly: auto-exposure makes it look normal.
      Instead `FacePulse.lighting` looks for the signs of sun on the face: the two sides' linear brightness ratio
      (≥ 3 = harsh) and the share of the face box blown out (luma > 0.96, ≥ 6% = harsh), majority of the last 6
      frames. Then Automatic skips the pulse, and the spoof model's "fake" no longer refuses (in any mode); the
      challenge decides. Thresholds unverified: Test recognition shows the side ratio and blown-out share. The pulse
      is also judged at its peak (4 peak frames) instead of after the fall, saving ~0.4 s, and the lead is 0.3-0.45 s.
      The unlock log lines (pulse, skipped, match, no match) are now `notice`, so `log show` keeps them.
    - *No background (2026-11-23, owner: spoof model at 1.00 yet always asked to blink):* the log showed "pulse
      passed=false no background". The two top-corner spots were unreadable (blown out or dark), and the MacBook Pro
      camera **can't lock exposure or white balance** (`isExposureModeSupported(.locked)` and even
      `.continuousAutoExposure` report false; mode 0), so there was no fallback. Now: 18 spots in a 6x3 grid over the
      upper frame, minus the head and body, each compared with itself and the median ratio used; with none readable,
      `relative` = centre gain over side gain − 1 (exposure scales both, so it cancels; a print or screen ~0) must be
      ≥ 0.04. Learned profiles are now relative to the face's sides in both cases (stored under a new key; the few
      learned the old way are dropped). Note for zsh: `log` is a shell builtin, use `/usr/bin/log show`.
    - *Glow (2026-11-23, owner: the swell only multiplies the wallpaper, so a dark one gives almost no light):* the
      light now comes from `FaceGlow`, a full-screen EDR Metal layer (rgba16Float, extended linear Display P3, 16x16
      drawable stretched) at the island's level − 1 in the same SkyLight space, so it's over the lock screen and
      under the island. Findings on this Mac (macOS 27.2): **ambient light sensor** reads with no entitlement through
      private IOHIDEventSystemClient calls (matching page 0xff00 usage 4, event type 12, float field 12 << 16; ~116
      lux in the owner's room). **EDR**: `maximumPotentialExtendedDynamicRangeColorComponentValue` = 16 at the
      owner's brightness; the current headroom climbs from 1.2 to ~5.5 over ~1.3 s once EDR content is shown, **even
      at alpha 0**, and stays up ~10 s after, so the scan shows an invisible layer as it starts (`warm()`) and the
      glow waits for the headroom (≤ 1.5 s) before starting. Physics: a 14" screen at 500 nits gives ~120 lux at
      50 cm, so the step needed grows with the room's light: share of peak = 0.08 + lux / 2000 (≤ 0.65), skipped
      over 1500 lux. The pattern is a random order of four low/high steps judged as the median of all high-window
      frames over all low-window ones, so `judge` is unchanged apart from the windows. **Unverified:** that the
      window shows over the lock screen (the island's own does, through the same space), that the headroom rises
      while locked, and every threshold on real faces with the new light. Test recognition → Check Light runs the
      real glow and shows the lux.
    - *Security levels (2026-11-23, owner):* the spoof model now runs on every frame (was every other) and decides
      first; the glow only runs when it's unsure (`FaceSecurity` holds every threshold). First Check Light on the
      owner's face (before the capture-time fix) read "no response to the light, depth −0.05, shape 0.00" with the
      spoof model at 1.00: frames had been stamped after analysis, 100 ms+ late against 0.2 s windows. They now carry
      the camera's capture time (a `CVBuffer` attachment set in `captureOutput`), and Check Light writes
      `~/Library/Application Support/Islet/light-check.csv` (per-frame window, commanded level, patches, background,
      frame luma). **Thresholds still guesses:** a photo and a phone video of the owner need scoring in Test
      recognition before Faster can be trusted.
    - *Face Unlock unreliable (2026-11-24, owner: re-enrolling fails at the end with "Try better light", it doesn't
      recognise me, Test recognition says "0.85 Fake / Spoof model: Fake 0.14" in a hoodie):* three separate causes.
      1. **Re-enrolment never saved.** The `face-embeddings` Keychain item's modification date was still 2026-11-19:
         no scan since had been stored. `security dump-keychain -a` shows the items' access lists name the Apple
         Development build that made them, with the installed Developer ID build added later ("Always Allow"), and
         the owner entry (`change_acl`) names no app. `KeychainStore.save` deleted the item and added it again; the
         installed app may read the item but evidently not delete it, so the add hit the existing item and the save
         failed, and `finishEnrolment` showed the consistency check's "Couldn't get a clear scan. Try better light"
         for both. Now `save` updates the data in place (`SecItemUpdate`, covered by the open `encrypt` entry and the
         Developer ID partition), falls back to delete and add, and logs each OSStatus (category `keychain`); a failed
         save says "Couldn't save the scan (Keychain error n)", and the enrolment's consistency is logged. The same
         path saves learned looks, which had the same problem. Not tested by hand here: writing to the owner's
         Keychain item from a test tool was refused, so the owner's next Scan Again is the test.
      2. **The spoof model refused the owner.** Every scan this morning logged `no match best=0 refused=true`, about
         2 s per attempt: the model, not the match (Test recognition scored the face 0.85 against a threshold of 0.50;
         18 learned scores, so the threshold hadn't started rising). MiniFASNet judges two crops of 2.7x and 4x the
         face box. On a laptop camera the 4x crop is most of the frame, so a hood round the face is in both crops and
         looks like the border of a print. The same face scored 1.00 without a hood on 2026-11-23. 1.6 had also made
         refusing much quicker: 1.5 refused when the mean of up to 12 values (every other frame, ~0.8 s) was under
         0.25, and 1.6 did it when 6 frames (0.2 s) were. A face the model wavers on (Test recognition moved between
         Fake and Unsure) dips under for 0.2 s almost every attempt. Now the mean of 20 frames (~0.7 s) has to be
         under the level's refuse line. On Standard and More secure, a face the model is sure is fake is doubted
         instead of refused: the glow has to vouch for its shape (a flat print or a screen doesn't answer it) and then
         the blink (or random challenge) has to be done too. Where the glow can't run (a bright room, no response
         earlier in the scan, harsh light already handled as before) or doesn't vouch, it's refused as before.
         Faster, which has no glow, still refuses. So a photo now has to pass the glow and the challenge, where before
         the model alone stopped it. **Unverified on the owner's camera:** a photo and a phone video of the owner need
         trying on Standard; if the glow doesn't answer the owner's face in a hood (Check Light), the hood still
         can't unlock, and it's the hood.
      3. **The learned threshold would have tightened too far.** Not the cause yet (18 of 20 scores), but with the
         owner's scores (lowest 0.71) Standard would have moved to 0.66 two unlocks later, and glasses or a hood
         that score ~0.6 would then fail before they could be learned (a look is only learned from an unlock). The
         threshold protects against other people, whose scores sit far lower; it does nothing against a photo of
         the owner, which matches anyway. Faster and Standard now stop at 1.5's ceiling (0.55 and 0.60); More secure
         keeps its 0.75.
      4. **Doubting came too late (same day, after the first fix):** the owner's re-enrolment saved (consistency 0.86),
         but every attempt logged "pulse lux=… share=…" and then "refused=true" ~0.25 s later, with no glow verdict.
         The glow started on the "unsure" path (the model needs 12 frames to be unsure but 20 to be sure it's fake),
         and the face could only be doubted while no glow was running, so when the model turned sure mid-glow the
         face was refused and the glow cut off. A face can now be doubted while the glow runs. Test recognition read
         the spoof model at 0.02 on the owner's real face at ~1000 lux, so the model is far from reliable on this
         camera; the scan now logs "doubted: spoof model …".
      5. **A bright room (same day, after the second fix):** the light sensor read 3800-4200 lux, so the glow was
         skipped and "Blink to unlock" shown, and ~0.6 s later every attempt was refused while the owner blinked: the
         model turned sure the face was fake, and only harsh light on the face (`FacePulse.lighting`) stopped its
         "fake" from refusing, not a room the sensor calls too bright for the glow. Now that counts too (Standard and
         More secure: the challenge decides, as it already did in harsh light); Test recognition says "Bright room:
         would ask". Not a broken install: there was one copy of the app, and the logs showed the code refusing.
      7. **Photo edge on the owner's own head (2026-11-24, logged by 1.7.1):** the test and real scans logged a rectangle
         at x 0.42 y 0.07, 0.16 x 0.42 of a 1920 x 1080 frame, confidence 1.00, the face box 0.15 x 0.27 inside it (face
         0.9 of its width, 0.63 of its height) while the spoof model said Real 1.00: the head's outline, not a photo. Seven
         scans were refused that way at 17:42. `PhotoCheck.hugs` now also needs the face to be at most half the rectangle's
         height, as in a photo or screen with room round the head. A tightly cropped photo no longer trips it; the spoof
         model and the glow are what judge those.
      6. **Straight to the blink in a bright room (owner, same day):** the scan only learned the room was too bright
         when it asked the service for the glow, after waiting ~0.4 s for the spoof model's first verdict. The service
         now reads the light sensor as the scan starts and tells the engine, which then skips the glow and the wait and
         asks for the blink as soon as the face matches (Standard and More secure; Faster is unchanged). A refusal now
         logs whether a photo edge or the spoof model did it: at 09:09 (1448 lux, just under the glow's limit) one
         attempt was refused with no "doubted" line, so the photo-edge check, not the model.
    - *Enrolment simplified (owner, 2026-11-24):* the embedder sees one aligned photo at a time and a scan scores
      against the closest three, so the circle of 8 directions was never required. Now: straight ahead (3), then up,
      down, left, right, one at a time (3 each), 15 samples.
    - *Replacing the spoof model (survey, 2026-11-24; nothing tried on this camera yet):* MiniFASNet fails the owner in
      bright light and in a hood. Candidates, all small enough for every frame:
      - **Intel Open Model Zoo `anti-spoof-mn3`:** MobileNetV3, 128x128 RGB (mean 151.2/119.6/107.8, scale
        63.0/56.5/55.0), output [real, spoof], 3.0 M params, 0.15 GFLOPs, ACER 3.81% on CelebA-Spoof, MIT. A different
        architecture and a different, much larger dataset (CelebA-Spoof: 625k images, many lighting conditions) from
        Minivision's. Intel's forum notes it's weak outside its demo; untested here. CelebA-Spoof itself is
        non-commercial research only, fine for this personal app.
      - **MiniFASNet retrained on CelebA-Spoof** (hairymax/face-antispoofing; suriAI/face-antispoof-onnx, 128x128,
        1.8 MB): same architecture as now, more varied training data. Licences to check per weights file.
      - ONNX re-exports of the current Minivision models (QingHeYang, garciafido) are the same model: no gain.
      No small passive model is reliable in direct sun; that's why a bright room now asks for the blink. Next step
      proposed: convert `anti-spoof-mn3` (and one CelebA-Spoof MiniFASNet) to Core ML next to the current one, show
      all scores in Test recognition, and try the owner's face (normal light, sun, hood) and a photo and phone video
      of it before swapping anything.
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
  **AirPods card, verified (2026-11-23, with a spike since removed):** it is not a
  notification. `com.apple.MenuBarAgent` opens a layer-101 window, 367 x 154 pt at the top right, whose `AXWindow` has
  identifier `smart-routing-system-banner`; inside, `AXStaticText` values "Marco's AirPods Pro" and "Moved to iPhone" and
  an `AXButton` "Undo" (`arrow.uturn.backward`). A connect card's texts are the name, the battery ("41") and
  "Connected", with no button. Control Center renders the same content off screen (y = 982) in an
  `AXHostedViewSceneWindow`. `AXCreated` arrives with the texts already in. Switching the AirPods to the iPhone and back
  fired no IOBluetooth connect or disconnect on the Mac, so the card's text is the only signal. Islet moved a "Connected"
  card's window to (-3000, -3000) as it does notification banners. **It doesn't hold (1.6 test builds, 2026-11-24):** the
  move reports success, but MenuBarAgent puts the card back at its place within a frame, every frame, for its whole ~4 s
  (moving it again every 16 ms only made it flicker at best). So the card is left to macOS, and since the notch's
  own "Connected" only repeated it, the Bluetooth connect event was removed with it (owner, 2026-11-24).
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


## Search from the notch (spike)

Owner request (2026-11-21): Islet's own search in place of Spotlight (DESIGN.md "Search"). Probes in
`Spike/SearchSpike.swift`: `-IsletDebugShape searchspike` (automatic; quits when done) and `searchkeys` (3 minutes of
the owner pressing the shortcuts). Log `~/Library/Logs/Islet-search-spike.log`: counts, timings and yes / no, never file
names or what was typed. Launch the debug copy with `open -n <app> --args …`: started straight from a shell, macOS holds
the shell's app responsible for Bluetooth and kills Islet for lacking the usage text.

39. **Apps?** Yes. A metadata query for `com.apple.application-bundle` returns 479 apps in 32 ms, but that includes copies
    inside other bundles; listing `/Applications`, `/System/Applications`, its `Utilities` and `~/Applications` gives the
    103 that matter in 1 ms. 72 of the 114 apps in those folders have `kMDItemLastUsedDate`, enough for the recent row.
    Icons: 50 in 50 ms with `NSWorkspace.icon(forFile:)` (cache them).
40. **Files?** Yes, through `NSMetadataQuery` (`kMDItemFSName LIKE[cd] "*text*"`, home folder): about 215 ms per query
    ("budget" 50 results, "xcd" 6). Stopping the previous query on each keystroke works: four keystrokes, final results
    220 ms after the last. Two limits: one letter is far too broad ("b": 195,806 results in 9.8 s, 86% under `~/Library`),
    so files start from two letters and `~/Library` is left out; a `BEGINSWITH` query is no faster (500 ms).
41. **Which folders?** Spotlight only returns files from folders the asking app may read: the debug copy (no Full Disk
    Access) got none from the Desktop or Downloads, where `mdfind` in a shell finds 3 and 7. The installed Islet has Full
    Disk Access for Messages, so it should see them. Still to confirm on the installed copy.
42. **Shortcuts?** `/usr/bin/shortcuts list --show-identifiers` lists all 8 with identifiers in 64 ms; `shortcuts run
    <id>` runs one. Their icons and colours aren't readable (`~/Library/Shortcuts/Shortcuts.sqlite` is off limits), so
    rows use one Shortcuts icon.
43. **Web search and Settings pages?** `x-web-search://` has no handler with Zen as the default browser, and a browser's
    search engine can't be read, so "Search the web" opens an ordinary search URL in the default browser, the engine
    picked in Settings. `x-apple.systempreferences:` links open System Settings at a page.
44. **⌘Space?** `RegisterEventHotKey` (Carbon, no permission needed) registers ⌘Space with status 0 even while Spotlight
    has it, and pressed by hand Islet did receive it, but none of the letters typed after it reached Islet's panel: Spotlight
    took the keyboard. So Spotlight's shortcut has to be moved, and registering can't tell whether it was. Reading
    `com.apple.symbolichotkeys` `AppleSymbolicHotKeys` entry 64 can: absent means the default (⌘Space, on); once the
    owner changes it the entry says enabled 0 or other keys.
45. **Letters typed straight after the shortcut?** All of them. With ⌃⌥⌘Space (free), the non-activating panel was key
    10 to 36 ms after the press, the front app stayed in front, and "abc" arrived complete and in order both times (first
    letter 688 and 304 ms after the press, typing as fast as possible). The panel taking the keyboard is far quicker than
    anyone types, so nothing is lost mid-animation.
46. **Handing the text to Spotlight?** Not directly: `NSWorkspace.showSearchResults(forQueryString:)` returns true but
    opens a Finder search window, not Spotlight (no Spotlight window appeared). The way left is to press Spotlight's own
    shortcut (read from entry 64, Q44) with a posted key event and paste the text, which needs Accessibility (the
    installed Islet has it). Not tried yet: it needs Spotlight's shortcut moved first. If it proves flaky, the Finder
    window is the fallback.

**Verdict:** feasible. Apps from the app folders, files from the Spotlight index (two letters or more, `~/Library` left
out), Shortcuts through the `shortcuts` tool, the calculator Islet's own. ⌘Space works once Spotlight's shortcut is
moved, and Islet can tell from the symbolic hotkeys whether it has been; typing straight after it loses nothing.
Still to try: files from the Desktop and Downloads in the installed copy (Q41), the Spotlight hand-off (Q46).

## iPhone Live Activities in the notch (spike, 2026-11-21)

Not built: dropped and removed from the code (owner, 2026-11-21). Kept as a record.

Owner request: the Live Activities macOS 26 shows from the iPhone (in the menu bar, and a card when clicked) in the
notch instead: the two sides in the wings, the card in the panel, and the menu bar's own one out of the way. Probed with
AX from a shell while a Cadence reminder's activity was up.

47. **Who draws them?** `MenuBarAgent` (`com.apple.MenuBarAgent`): each activity is an item of its `AXExtrasMenuBar`,
    role `AXMenuBarItem`, subrole `AXLiveActivity`, identifier `live-activity-pill-com.apple.chrono.WidgetRenderer-Activities`,
    description the app's name ("Cadence"). No window of its own shows in `CGWindowListCopyWindowInfo` (status items are
    drawn into the menu bar window on macOS 26).
48. **Can the compact sides be read?** Yes, as accessibility, not pixels: two groups (leading, trailing), each a hosting
    view with an `AXImage` (only a description: "Checklist With Checkmarks") or `AXStaticText` ("1:37:23"), plus an
    "Expanded" image. The text updates every second (read 2 s apart: 1:37:48, 1:37:50). The image itself isn't exposed.
49. **The expanded card?** `AXPress` on the item opens it: a window with identifier `live-activity-expanded` (408 x 960, an
    `AXLiveActivity` group 299 x 117) whose hosting view lists every text with its size (the title, "OVERDUE", "Reminder
    went off at 9:00 AM", the timer, "Important", the notes) and the app's buttons ("Complete", an `AXButton`). Colours,
    fonts and layout are not exposed.
50. **Can Islet move or hide the menu bar item?** Not through AX: its position and size aren't settable. Still to try: hiding
    it in System Settings > Menu Bar (does the activity still exist to read?).
    **No setting for it (2026-11-21, owner checked the whole page):** macOS 26.2's Menu Bar settings carry the strings for a
    "Live Activities" section (`LIVE_ACTIVITIES_SECTION_DESCRIPTION`), but the page doesn't show it, and Live Activities
    aren't in "Allow in the Menu Bar". The only switch is Notifications > "Allow Live Activities from iPhone", which stops
    them reaching the Mac at all. ⌘-dragging the pill out of the menu bar doesn't remove it either (owner tried).
51. **Seeing them as they look** would need their pixels: ScreenCaptureKit can capture a window even when it's covered,
    but that needs Screen Recording permission, and the menu bar item has to be on screen to be captured. Not tried.
52. **Opening the card off screen?** Half the time. The card's window (`live-activity-expanded`) is created 26 ms after the
    press and its position is settable: moved from the `AXCreated` callback it reached (-3000, -3000) by 74 ms the first
    time; the second time the move returned success but the window stayed at (738, 34), on screen. macOS seems to place
    it itself just after creating it. To try when building: move it again on `AXMoved` / `AXWindowCreated` until it stays.
    While open it stays readable and live (all 7 texts, the timer counting). Esc doesn't close it reliably; pressing the
    menu bar item again does.

**Verdict so far:** Islet's own layout is feasible for any activity: the two sides and the card's text and buttons can
be read, live. Still open: hiding the menu bar's copy (owner to try System Settings > Menu Bar), and keeping the card off
screen while it's read (Q52).

## Calls answered on the iPhone (probe, 2026-11-21)

Not built: calls were dropped (owner, 2026-11-21). Kept as a record.

Owner question: can the notch show an active call however it was answered, on the Mac or on the iPhone? Probe (a script
kept out of the repo) logged every 0.5 s: call banners in Notification Center, FaceTime / Phone windows, call-like menu
bar items, the Dock, the microphone. The owner made three phone calls and a FaceTime call answered on the iPhone, then a
phone call answered on the Mac.

53. **Phone call answered on the iPhone:** the Mac's banner rings as usual (the caller's name, and Answer, Decline, Decline
    with Message, Live Voicemail, all pressable). When the iPhone answers, the banner reads "Mom, Call Answered on
    iPhone" for about 3 s, then goes. After that the Mac shows nothing of the call: no window, menu bar item, Handoff or
    microphone. So Islet learns who and when it started, but not when it ends. Trying to answer on the Mac then shows
    "Use your iPhone / Cannot answer on this Mac".
54. **FaceTime answered on the iPhone:** the banner rings (AvatarView "FaceTime Audio", "Mom, FaceTime Video", Answer /
    Decline pop-up buttons), goes when the iPhone answers, and then the Dock shows a **Handoff item** (`AXDockItem`,
    subrole `AXHandoffDockItem`, title "Phone") for as long as the call lasts (11:37:55 to 11:38:14 here, about the call's
    length). So an iPhone FaceTime call can be followed: who (from the ring), how long (from the answer), and its end (the
    Handoff item going). Pressing the Handoff item should move the call to the Mac (not tried).
55. **Phone call answered on the Mac:** the banner becomes the call's controls: "Phone", "Mom, 0:01" (name and time),
    FaceTime Video, Mute, Keypad, More, End; the microphone is in use for the call (11:38:33 to 11:38:48). As in Q31.
56. **When an iPhone-answered phone call ends:** not seen on screen. The synced call history
    (`~/Library/Application Support/CallHistoryDB/CallHistory.storedata`) may get the call with its duration when it
    ends; it needs Full Disk Access (Islet has it; the probe's shell didn't). To try: how soon the row appears.

**Verdict:** calls on the Mac (phone or FaceTime) can be shown fully, with controls. A FaceTime call on the iPhone can be
shown with name and timer, ended by the Handoff item. A phone call on the iPhone can be shown starting, but its end can
only come from the call history, if that syncs quickly enough (Q56).

## Tapbacks, read receipts and emoji in the conversation (2026-11-22)

Owner request: read receipts, right-click to react like Messages, and emoji in replies. Probed Messages (macOS 27.2) with
a small Accessibility tool from the shell; nothing was sent.

57. **Can Islet send a tapback?** Not through Apple Events (Messages' dictionary has no command for it), but through
    Accessibility: each bubble in Messages' window is an `AXGroup` whose description is "Your iMessage, <text>, <time>"
    (yours) or "<Name>, <text>, [You loved this,] <time>" (theirs), with actions `AXShowMenu` and named ones (Reply…,
    Copy, Edit…). `AXShowMenu` opens its menu with the tapback row as `AXMenuItem`s identified `heart`, `thumbs_up`,
    `thumbs_down`, `ha_ha!`, `exclamation_mark`, `question_mark`, then a row of recent emoji (identified by the emoji)
    and a button for any emoji. A walk of the window takes about 0.1 s natively (18 s through System Events). The menu
    only opens with Messages in front and the conversation showing, so Islet opens it (`sms:` for a one-to-one chat;
    a group has to be open in Messages already), presses the tapback, and brings back the app that was in front.
    Edit > "Tapback Last Message…" (⌘T) also exists but only reaches the last message.
58. **Reading reactions:** rows with `associated_message_type` 2000-2005 (heart … question), 2006 (any emoji, in
    `associated_message_emoji`, macOS 15 on) and 3000-3006 (taking one off); `associated_message_guid` is
    "p:<part>/<guid>" or "bp:<guid>" of the message. Each person has one at a time, so the newest row per person wins.
59. **Read receipts:** your message's `date_read` is set (ns since 2001) once the other person read it, if they share
    read receipts; Messages shows "Read <time>" for today, "Read Yesterday", a weekday within a week, else a date.
60. **Emoji while typing:** Islet is an agent app with no Edit menu, so ⌃⌘Space (Emoji & Symbols) did nothing in the
    reply field; Islet now opens the picker itself (`NSApp.orderFrontCharacterPalette`). Typing a word first and then
    ⌃⌘Space searches the picker for it, as in other apps.

## Pointer on the desktop (1.4.1, 2026-11-23)

Owner report: on a Mac without a notch the island didn't answer the pointer at the top of the screen while on the
desktop. Islet tracked the pointer with a global `mouseMoved` monitor, and macOS only delivers moves to global monitors
while the frontmost app asks for them, which the desktop (Finder with no window) doesn't. Now a listen-only
`CGEventTap` (session, tail, mouse moved and dragged) feeds the same check; it never holds or changes events, and
re-enables itself if macOS disables it. Not reproduced on the owner's Mac by hand yet. Ruled out: the Mission Control
check (`DockOverview`) misfiring; on macOS 27 Mission Control adds a full-screen Dock window at layer 20 and the menu
bar window stays listed, so "menu bar showing" can't tell them apart either.

## Battery stats (1.5, 2026-11-23)

- **Temperature**: macOS 27 no longer has `Temperature` in AppleSmartBattery's registry entry. The SMC still has it:
  `TB0T`, `TB1T`, `TB2T` are `flt ` (°C) and readable by any process through AppleSMC's user client (selector 2,
  the 80-byte `SMCKeyData_t`; Swift needs explicit padding after `keyInfo` to match C's offsets). They read 25.8 °C
  here, the 78 °F a third-party battery app showed. `SMCSensors.temperature` averages the ones that answer.
- **History**: there's no public battery history (System Settings' chart comes from powerlog, root only). `pmset -g
  log` is readable by any user and notes `Using Batt (Charge:41%)` / `Using AC(Charge: 41)` at every sleep, wake and
  assertion summary: about 3,600 lines over several days, ~4 s of CPU to read. Islet records its own samples and
  reads the log only when its own have a gap (after a quit or on first run), off the main thread.
- **Time since unplugged**: nothing in IOKit says when the charger came out. The first `Using Batt` line after the last
  `Using AC` one gives it to within a few minutes; Islet's own samples give it exactly when it was running. It matched
  the third-party app's 26 hr 43 min.
- **Power in**: `PowerTelemetryData.SystemPowerIn` (mW) is what the charger delivers; 0 on battery.
- **Live power**: the battery's registry entry (Amperage, PowerTelemetryData) only refreshes about every 30 s
  (`UpdateTime` didn't move over five one-second reads), so its watts looked frozen next to another app's. The SMC's
  are live: `PSTR` the whole system (9-14 W from second to second here), `PDTR` the charger's input (57.9 W), `SBAP`
  the battery (-44 W while charging, so the SMC signs it the other way: into the battery is negative). At rest they add up
  (`PDTR` = `PSTR` - `SBAP`), but `SBAP` isn't kept in step: under load it read 64 W against 58 W in. So the stats'
  diagram takes the Mac's draw and the charger's input and works the battery's share out as the difference.

## Menu bar position (1.5, 2026-11-23)

A new status item is inserted at the left end of the menu bar's items. With a full menu bar on a notched Mac that is
behind the notch, so it's there but can't be seen (on macOS 27 the items are drawn by MenuBarAgent, so Islet's own
window list doesn't show them either). macOS stores an item's place as `NSStatusItem Preferred Position <autosave
name>` (points from the right edge) in the app's own defaults, and reads it when the item is made: Control Center's
own were Clock 105, BentoBox 96, ScreenMirroring 171. Islet sets 230 for its item ("IsletMenuBarItem") when there's no
value yet, then sets the autosave name. A ⌘-drag writes the key, so the owner's own placement wins after that.

## Shazam (2026-11-23)

- `SHManagedSession` (macOS 14) records from the microphone itself and answers with `SHMatch`, no match, or an error;
  `prepare()` warms it up. It needs `NSMicrophoneUsageDescription` and, under the hardened runtime,
  `com.apple.security.device.audio-input`, or it hears silence. Islet stops it after 15 s and calls that no match.
- Matching against Shazam's catalog needs the **ShazamKit App Service** switched on for the App ID
  (`com.marcogad.islet`) at developer.apple.com > Identifiers; Xcode's automatic signing doesn't do it. Without it
  every attempt fails (expected `SHErrorDomain` 202, `matchAttemptFailed`), which the notch shows as "Couldn't reach
  Shazam". Not yet tried on this Mac: check the `shazam` log category the first time.
- Only the microphone: music playing on the Mac through headphones isn't heard. Hearing the Mac's own sound would
  take a Core Audio process tap (`AudioHardwareCreateProcessTap`, macOS 14.2+, its own "System Audio Recording"
  permission) fed to `SHSession.matchStreamingBuffer`. Not built.
- `SHLibrary.default.addItems` puts a match into the user's Shazam library (synced with the Shazam app's history).

## Mac Stats (1.7, 2026-11-24)

Read on this Mac (Mac16,8, M4 Pro, 4 efficiency + 8 performance cores shown by other apps) through AppleSMC's user
client, as `SMCSensors` already does, with no special rights:

- **Fans**: `FNum` = 2 (`ui8`). `F0Ac`/`F1Ac` (actual rpm, `flt`) read 0.0 at idle: Apple silicon stops the fans when
  cool. `F0Mn`/`F1Mn` 2317, `F0Mx`/`F1Mx` 7826 rpm. `F0Md` = 3 (`ui8`), `Ftst` = 0.
- **Temperatures** (`flt`, °C): `Tp01`/`Tp05`/`Tp09` 40.0 (performance cores, they move in steps), `Te05` 44.8
  (efficiency), `Tg05` 44.4 (GPU), `TCMb` 47.9 / `TCMz` 63.2 (unknown: possibly memory or the SoC). `TC0P` (the Intel
  CPU key) doesn't exist. The full list of `Tp*`, `Te*`, `Tg*` keys has to be enumerated (SMC key count `#KEY`, then
  read keys by index) rather than hard-coded, since it differs per chip.
- **Power**: `PSTR` 8.45 W, as in "Battery stats".

Still to check before building (the spike in ROADMAP 1.7):

- **Fan control** needs root: writes through the SMC user client are refused for a normal process. Other tools install
  a privileged helper (here: an `SMAppService.daemon` with a launchd plist, approved in Login Items) and, on M-series,
  write `Ftst` = 1, then `F<n>Md` = 1 (manual) and `F<n>Tg` (target rpm), and `Ftst` = 0 to give control back. Check
  on this M4 Pro: whether that works, whether macOS overrides the target when hot (the Fans page promises it does),
  and that sleep, quit and a crash of the app all hand the fans back (the helper should reset them itself when its
  client goes away).
- **CPU use per core**: `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` ticks, differenced; which cores are which from
  `sysctl hw.perflevel0.logicalcpu` (performance) and `hw.perflevel1.logicalcpu` (efficiency), assuming efficiency
  cores come first in the list (check). Speed: IOReport "CPU Stats" residencies, or leave it out.
- **GPU**: `IOAccelerator`'s `PerformanceStatistics` ("Device Utilization %", "In use system memory") without rights.
  Per-app GPU use and the frame rate have no obvious public source: find one or drop those rows. Neural Engine use:
  IOReport, maybe only power.
- **CPU and GPU watts**: IOReport "Energy Model" channels, said to work without root. `powermetrics` needs root: not
  used.
- **Memory**: `host_statistics64(HOST_VM_INFO64)` for the breakdown, `sysctl vm.swapusage`, and pressure from
  `kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical) or a `DispatchSource` memory-pressure source.
- **Top apps**: `proc_listallpids` + `proc_pid_rusage` CPU time and footprint, differenced between refreshes; names and
  icons from `NSRunningApplication` where there is one.
- **Cost**: all of this every 2 s while the panel is open, and only what the menu bar shows otherwise. Measure Islet's
  own CPU use with everything on.

### Spike results (2026-11-24, M4 Pro, macOS 27.2)

The probe tools were throwaway command-line programs, not kept in the repo.

**Fan control works, with root.**
- As a normal user every SMC write is refused with `kIOReturnNotPrivileged` (0xE00002C1), even writing a key's
  current value. With root:
  1. `F0Md` = 1 straight away is refused with SMC result 130.
  2. `Ftst` = 1 is accepted. On its own it sets both fans to mode 0, target = their minimum (2317), and they start.
  3. `F<n>Md` = 1 is refused for about 6 s after that, then accepted (the test retried every 0.5 s; the 12th try
     took). Build the helper to retry for up to ~10 s.
  4. `F<n>Tg` (`flt`, little-endian) is then followed: 0 → 3,500 rpm in about 3 s, held within ±25 rpm.
- **Handing back**: `F<n>Tg` = 0 and `Ftst` = 0. `F<n>Md` = 3 can't be written (result 130), and doesn't need to be:
  about 3 s after `Ftst` = 0 the SMC sets the mode back to 3 itself and the fans spin down and stop.
- **A crash leaves the fans held.** The test exited with the fans at 3,000 rpm and nothing reset them for the ~50 s
  until a manual reset. So the helper (a root `SMAppService.daemon`) must hand back by itself: when the app's XPC
  connection drops, when it hasn't heard from the app for a few seconds (a heartbeat while not Automatic), at its own
  start (so launchd relaunching a crashed helper fixes it), and on sleep and shutdown. Still untested: whether sleep or
  a restart clears `Ftst` on its own, and whether the SMC overrides the target when the Mac gets hot (the Fans page
  promises that; if not, the helper does it, from the CPU temperature).

**Everything else is readable without rights:**
- **Cores**: `hw.perflevel0` = 8 Performance, `hw.perflevel1` = 4 Efficiency. In `host_processor_info` the 4
  efficiency cores come first (0-3, read 76/74/72/68% at idle), then the 8 performance cores.
- **GPU**: `IOAccelerator` `PerformanceStatistics`: "Device Utilization %", "Renderer/Tiler Utilization %",
  "In use system memory" (974 MB). Per app: each `AGXDeviceUserClient` has `IOUserClientCreator` ("pid 616,
  WindowServer") and `AppUsage` with `accumulatedGPUTime` (ns): difference it between samples. No frame rate anywhere
  found: drop that row from the GPU page.
- **Watts**: IOReport group "Energy Model" works without root (link `-lIOReport`, declare the functions with
  `@_silgen_name`). Over 3 s: "CPU Energy" 1.35 W (mJ; also `EACC_CPU` efficiency, `PACC0_CPU`/`PACC1_CPU`
  performance clusters), "GPU Energy" 0.10 W (nJ), "ANE" 0 (mJ). CPU energy only updates about once a second (a 1 s
  delta read 0), so use a 2 s or longer window.
- **Memory**: `kern.memorystatus_vm_pressure_level` = 1 (normal); `vm.swapusage` used 695.75 MB.
- **Temperatures**: `#KEY` = 3374 keys; enumerate by index (command 8) and keep `T*` `flt` keys. CPU: about 50
  `Tp**` (38-75 °C at once: some are hot spots) and `Te0*`/`Tex*` (efficiency); GPU: about 20 `Tg**` (37-45 °C);
  also `TB*` battery, `TaL*`/`TaR*` airflow left/right, `TPD*`/`TRD*`/`TUD*`, `Ts**`. Which ones make the panel's "CPU"
  and "GPU" (average and hottest) is still to settle against iStat Menus' figures, which this Mac has.
- **Fans**: also `F<n>St` (3 at rest), `F<n>Dc`, `FOff` = 1. `F<n>Ac` is the speed to show.
- **Processes**: a normal app's `proc_pid_rusage` and `proc_pidinfo` read 871 of 1,187 processes here, not root's
  (WindowServer, launchd); `/bin/ps -axo pid=,%cpu=,rss=,comm=` lists them all. So `ProcessReader` takes the list and
  CPU from `ps` (its %cpu is a recent average, as Activity Monitor's) and the memory footprint from `proc_pid_rusage`
  where it can, else `ps`'s resident size. Run only while a page shows the lists.

**Fan helper design (1.7, built 2026-11-24, not yet run)**: `SMAppService.daemon(plistName:)` rather than Energy Mode's
sudoers rule, because the fans need a process that stays and watches: launchd starts it when the app connects (Mach
service `com.marcogad.islet.fanhelper`), relaunches it after a crash (`KeepAlive` `Crashed`), and it exits after a minute
idle with the fans automatic. The listener only accepts Dynamic Peninsula signed by team L4Y6A9NY9T
(`setConnectionCodeSigningRequirement`), and the app only trusts the helper's identifier. The team in both rules is the
checker's own (`SecCodeCopySigningInformation`): Debug builds are signed by the development team (L4Y6A9NY9T), releases
by Developer ID (X9Q5Y948RX), so a fixed team would have shut a release out of its own helper. `make-dmg.sh` signs the
helper before the app. Checked with `codesign -v -R` on both builds (and `/bin/ls` is refused). To check on the first run: that registration
works from a Debug build in DerivedData, what Login Items shows for it, and that the 6 s take-over doesn't trip XPC
timeouts.
