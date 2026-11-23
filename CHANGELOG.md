# Islet release notes

Newest first. `scripts/release.sh <version>` publishes the section for that version as the GitHub release notes, so add
the section before releasing. Ideas and bugs found while testing go into the next version.

## 1.5 (unreleased)

### Menu bar battery

- Islet's menu bar icon can be a battery instead of the pill: turn on "Battery in the menu bar" in Settings > Battery (or in the features list), so it can stand in for the macOS battery icon and not take up a second spot. It draws like macOS's: the charge as a fill, a bolt while charging, a plug when plugged in and not charging, red at 10% and yellow in Low Power Mode, with the percentage beside it (can be turned off). Settings has a shortcut to Control Center settings, where you hide the macOS one.
- Click it for battery stats: time left or to full, time since unplugged, power source, cycle count, temperature, battery health, a chart of the last 12 hours, and a live diagram of where the power is flowing: from the battery, the charger or both into the Mac, and from the charger into the battery while it charges. Or set the click to open the control center, as from the notch. Right-click still gives Islet's menu.
- Charging shows the moment the battery says so: Islet reads the battery's own charging flag instead of waiting a second or two for macOS's power list. The stats and the battery page update every second from the Mac's live power sensors (the battery's own figures only change every 30 seconds or so), and at once when a charger goes in or out.
- The chart starts full: the hours before Islet was running come from macOS's power log. Islet keeps a day of charge history on the Mac (Application Support/Islet); nothing leaves it.

### Fixes

- Macs without a notch: the island now answers the pointer at the top of the screen while you're on the desktop. macOS doesn't send pointer moves to other apps while the desktop is in front, so Islet now also watches them another way.
- Search opens with ⌥Space by default, so it doesn't take ⌘Space from Spotlight. You can still give it ⌘Space in Settings > Search.
- Contacts permission: pressing Allow now asks for access. Before, the app was missing the Contacts entitlement its signing needs, so macOS refused silently and System Settings showed an empty Contacts list.

### Face unlock

- Face unlock now only uses the MacBook's own camera. An iPhone (Continuity Camera), a USB webcam or a virtual camera could be fed prepared video, so they're never used.
- New "Automatic" liveness check, now the default: once your face matches, the screen brightness swells gently once and comes back. A real face lights up by its shape (the face more than the room behind it, the middle of your face more than its sides); a photo or a phone screen doesn't. When that and the new spoof model agree, it unlocks with nothing to do. Otherwise (a bright room, say) it asks for a blink, smile or head turn as before.
- A spoof model (Minivision's MiniFASNet, runs on the Mac) refuses faces it's sure are a print or a screen, in every mode. Settings > Face Unlock can turn it off.
- It learns how your own face responds to the light, and after 8 unlocks a different face shape isn't vouched for.
- Optional: "Raise the threshold as it learns my face". After 20 unlocks the match threshold moves up to just under your usual scores (at most 0.15 above the slider). Only your own confirmed unlocks move it.
- Test recognition shows the spoof model's verdict, and Check Light runs the brightness check and shows what it measured.
- In direct sun, Automatic skips the brightness swell and asks for the blink (or smile, or turn) straight away: it spots sun on your face from one side being much brighter than the other, or blown-out skin. The spoof model doesn't refuse your face in that light either; the challenge decides. Test recognition shows when it sees harsh light.
- Settings > Face Unlock > "When a challenge is needed, just ask me to blink" (under Automatic): the fallback is always a blink instead of a random blink, smile or head turn. Off by default.
- The light check works in more rooms: it reads the room from spots all around your head instead of two corners, and when none is readable (bright lights or windows behind you) it compares the middle of your face with its sides instead of giving up. Before, a blown-out corner meant it always asked for a blink, even with the spoof model sure you were real.
- The light check is quicker: it decides as soon as the swell peaks instead of waiting for the screen to come back, and once it gets no response in a scan, the next tries go straight to the challenge.

## 1.4 (2026-11-22)

### Notifications

- Banners show under the notch instead of the top-right corner, and still go to Notification Center. The title and message sit in a wide bar under the wings, or in the chin when the menus are wide.
- Hover for the full card, click to open it, swipe up to dismiss.
- When several arrive at once, they stack: the next one tucks underneath, then the notch shows "2 more", "3 more".
- Opening the panel always shows the controls (or music). Waiting notifications ride along as a pill at the top. Click it for the full list, with Clear all and a back button.
- The banner's own buttons come along, such as approving a Duo sign-in from the card or the list (never from the small bar).
- iPhone notifications get an iPhone icon, and time-sensitive ones say so in orange.

### Messages

- Click a message (or Reply) and the conversation opens under the notch, with contact names and a reply field that sends through Messages.
- New messages appear as they arrive.
- Read receipts: your last message says "Read 2:31 PM" once they've seen it (when they share read receipts).
- Right-click a message to react with a tapback, or "Other Emoji in Messages…" for any emoji. Reactions show on the bubbles.
- Emoji in replies: the smiley button or ⌃⌘Space opens Emoji & Symbols. Type a word like "smile" first to search for it.
- Two fingers scroll lists in the panel (conversations, notifications, Wi-Fi, Bluetooth). Swiping up only closes the panel once the list can't scroll further.

### Music

- Music leaves the notch while its app is in front, and comes back when you switch away.
- When you've swiped music away, hovering the notch shows the album's colours instead of the old green dot.
- Hovering music in the wings turns them into a wide bar with the song's name.
- Swipe left or right with two fingers to change songs. It follows your fingers, the trackpad taps halfway, and it slides back if you don't go far enough.

### Charging

- Plugging in, the percentage rolls up from empty as a battery fills beside it, and the bolt springs in on top just as it lands. Low battery rolls down and drains in red.

### Search from the notch (⌘Space)

- It finds:
  - apps, with the 7 you used last waiting under an empty field;
  - files, Shortcuts and System Settings pages;
  - answers to sums;
  - Spotlight and web searches, in the last two rows.
- Keys: arrows move, Return opens, ⌘Return shows it in Finder, Tab completes, Esc clears and then closes.
- Typing works straight away: letters show while it opens. Typing in the open panel starts a search too.
- Contacts:
  - Return opens the person in Contacts.
  - Message, Call, FaceTime and Email buttons sit on the right.
  - "call mom", "text mom", "facetime mom" and "email mom" do that on Return. A text opens the conversation in the notch.
- Settings warns when Spotlight still has the shortcut. You can pick another shortcut, turn it off, or choose the web search engine.

### Settings redesign

- Pages in a sidebar, with Islet's status on top: "Everything is set up", or "N things need attention" with the fix for each.
- Permissions fold into one line while they're all allowed. One that's off shows on the pages it breaks, with a badge in the sidebar.
- Face Unlock has its own page.
- Islet checks permissions again whenever the window comes to the front.

### The panel

- When the menu bar has room, the panel opens flush with the top of the screen, growing straight out of the notch with
  its header beside the camera. With menus or icons in the way, it hangs under the notch as before.

### Pick your features

- Setup starts by asking what you want Islet to do: volume and brightness, notifications, Messages, Focus, search and
  Face Unlock. It then asks only for the permissions those need, each listed once with what it's for.
- Settings' Islet page lists every feature with a switch and how it's doing ("Ready", "Needs Full Disk Access").
  Turn one off and Islet stops asking for what only it needs. Permissions are grouped into what your features use
  and what they don't.
- Search's shortcut is a plain choice: take over ⌘Space (Spotlight moves) or keep ⌘Space for Spotlight and use
  another one for Islet. Settings and setup show what's true right now and tick themselves off once Spotlight moves.

### Quick info

- Move the pointer over the notch while nothing is showing to see the time and date, the battery, and your Wi-Fi network
  and Bluetooth device. Click and they glide into their places in the panel as it opens. Turn it off in Settings >
  Notch.

### Ask Siri

- Type "siri" and a question in search, or just a question, and press Return: Islet opens Spotlight with it asked,
  and Siri answers there. When search finds nothing, Ask Siri comes first too. (macOS 27; turn it off in Settings >
  Search.)

### Fixes

- Plugging in the charger shows the charging animation straight away. Before, it waited a couple of seconds for macOS to
  work out the time to full; that now fills in once it's known.
- Clicking a notification in the panel's list now opens it in place, with its whole message and its buttons (Open, Reply, or the app's own). Before, it opened the app behind the panel and left the list showing.
- Without a notch, the chevron no longer drops down over Mission Control when the pointer reaches the top of the
  screen, so the windows and Spaces up there can be clicked.
- Swiping music away while hovering the notch: the song's name now fades as the notch pulls in, instead of showing on
  the desktop under it (and sometimes staying there).


## 1.3 (2026-11-20)

- Glass look: like Siri's island on the iPhone, the island stays black and a strip along its bottom edge fades into
  glass, the desktop showing through blurred, with a light rim and a soft coloured glow. The panel's tiles and buttons
  are glass too. Turn it off in Settings → General → "Glass look".
- Battery page: click the battery in the panel's header for the charge and what it's doing, maximum capacity, cycle
  count, the charger's wattage or how much power the Mac is drawing, and the time to full or left, kept live while the
  page is open. With a charge limit set in Battery settings, it shows the limit (click it to change it there), times
  charging to the limit, and says when it's holding there.
- Energy Mode on the battery page: switch between Low Power, Automatic and High Power for the power source you're on.
  The first switch asks for your admin password once; after that it's instant (Settings → General can take that
  permission away again).
- The panel closes when one of its Settings… buttons opens System Settings, so the window isn't left under it.
- Cleaner Wi-Fi, Bluetooth, Screen Mirroring and Sound pages: no grey box, the page sits straight on the island, with
  Control Center style rows that light up under the pointer and the one in use on a glass pill.
- The notch answers the pointer whatever it is showing: hover over the wings, the wide bar or the chin and it swells a
  little with a springy bubble, then settles back when you move away. It reacts straight away, even in the middle of
  an animation (wings springing out, the chin dropping), instead of waiting for it to finish. What it shows grows
  with it, so the spacing stays even.

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
