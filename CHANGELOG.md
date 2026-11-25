# Islet release notes

Newest first. `scripts/release.sh <version>` publishes the section for that version as the GitHub release notes, so add
the section before releasing. Ideas and bugs found while testing go into the next version.

## 1.7.1 (unreleased)

- **Smoother Mac Stats charts.** Only each chart's newest point eases to a new reading now each reading settles in 0.45 s instead of 0.7 s, and the numbers change without rolling, which takes the CPU page from about 50% of a core to about 25% while it is open.
- **Longer swipes for skip and Shazam.** The two-finger swipe over media and the one that pulls Shazam in need more travel on the trackpad before they complete.
- **Face unlock works from further away.** The camera now captures at 720p instead of 640 x 480, and a face counts from 11% of the frame's width instead of 14%. It also logs the face's width and match score while scanning, to tune the range.
- **Faster face unlock in bright light.** The light sensor gets a moment to answer before a scan starts, so a bright room goes straight to the blink instead of waiting on the spoof check and the glow first.
- **The display stays awake while a scan runs,** so it no longer goes to sleep from inactivity half way through an unlock.
- **Glass look and Extended brightness are on the General settings page.** They were under Notch.
- **Choose which stats warn.** Under "Warn in yellow and red" in Settings > Mac Stats, each stat (efficiency cores, performance cores, GPU, memory, temperature) has its own switch, so a part you don't care about never turns yellow or red, in the menu bar or the panel.
- **The overview's bars and graphs grow in.** Each time the Mac Stats overview is shown, the CPU and memory bars grow to their readings and the two sparklines rise from their baselines. The captions under the numbers just change now, without a text effect, which takes the overview from about 50% of a core to about 30%.
- **"CPU 0.0 W" in the Power tile is fixed.** The CPU's energy counter only moves about once a second, so a reading taken soon after another showed 0 W. Readings now cover at least 1.8 s.
- **The Power tile no longer bounces between two heights.** CPU and GPU watts each have their own line, so the tile is always the same size.
- **"100%" stays on one line** in the CPU tile on the Mac Stats overview.
- **The screen no longer stays dim after opening the lid.** The face scan's dark-room boost now waits until the display has finished waking and the camera has settled, so it can't save a half-faded brightness and put the screen back to it.
- **Smoother bubble on Macs without a notch.** The liquid neck that joins the card to the top edge is now drawn over a small area instead of the whole panel.
- **Page transitions in Mac Stats.** Opening a page or going back now drifts a few points sideways as it fades, instead of a plain fade.

## 1.7 (unreleased)

### Extended brightness

- **Brighter than 100 on an XDR MacBook Pro.** At 100, hold the brightness-up key for a second and the whole screen goes past it, up to 160, using the display's HDR headroom. A red bar fills over the white one from the left to show how far, and the number counts on past 100. Brightness-down takes the extra off first, then the white bar as usual.
- **It shows you how.** Reaching 100, the bar bumps against its end and then suggests holding the key for XDR brightness. Holding fills the bar with red and the sun swells until it unlocks with a flash.
- **The Display page knows.** The brightness slider in Controls and on the Display page shows the extra in red with an XDR label, and the Display page says it uses more battery and heat, with a Turn Off button.
- It turns itself off when the screen sleeps or locks, the lid closes, below 20% battery, or when the Mac runs hot, and never stays on after a restart. Settings > Notch > Extended brightness turns it off.

### Mac Stats

- **Your Mac's vitals in the menu bar.** Turn on Settings > Mac Stats (or Mac Stats in the features list) for one compact menu bar item beside the battery: the CPU temperature over what the whole Mac is drawing, the fan speed, then bars for the CPU (one bar, its halves the efficiency cores in green and the performance cores in blue), the GPU (purple) and memory (cyan).
- **Warnings you can't miss.** A bar turns yellow above 70% and red above 90% once it has stayed there a few seconds, and memory by memory pressure rather than by how full it is. The temperature turns yellow from 80 °C and red from 95 °C.
- **Click for the details.** A panel like the battery stats: CPU, GPU, memory and power at a glance, temperatures and fans. Click a part for its page: the last 10 minutes, each core, the memory breakdown, and the apps using the most.
- **Names you can read.** The app lists add helpers up under their app (Claude, not "Claude Helper (Renderer)"), with its icon, and give macOS's own processes a plain name, with the real one underneath: "Drawing the screen" (WindowServer), "Spotlight indexing", "Sound".
- **Control the fans.** Turn on "Let me control the fans", install the small fan helper once, and the Fans page gets Automatic, Manual (one slider for both fans) and Full Speed. The fans always go back to Automatic when Dynamic Peninsula quits, the Mac sleeps or restarts, or the CPU gets too hot.
- **Every part can be switched off** on its own in Settings > Mac Stats, with how often it updates and whether it uses colour.
- **Quit what's using the most.** On the CPU and Memory pages, hover a row and click ⓧ to quit it. If it won't quit, the row offers Force Quit.
- **It all moves smoothly.** The panel fades in as it drops into place. Numbers roll up or down to each new reading, bars ease, and every graph glides to each reading and slides along as time passes. Pages fade in as the panel settles to their size, the app lists stay put unless one app clearly passes another, and tiles and buttons respond to the pointer. Reduce Motion keeps it still.

### Fixes

- **Much less CPU while idle.** Once the battery stats had been opened, their power-flow animation kept redrawing out of sight, keeping Dynamic Peninsula near 20% CPU. The menu bar panels now let go of their contents when they close.
- **The menu bar stays still.** The Mac Stats item keeps the same width as its numbers change, so the icons beside it no longer shift.
- **Switching fan modes quickly works.** The newest choice wins. Automatic can call off a takeover that's still starting, and a fan the system was still handing back is taken over again.
- **Clicks reach the top of the screen on Macs without a notch.** With "Bubble from the top edge" on, hovering the top strip (a full-screen browser's tab bar, say) used to block clicks across 260 pt, so a tab's close button didn't work. Now only the small pill itself takes clicks and the two-finger swipe down; the rest of the strip stays clickable.
- **Typing a Wi-Fi password no longer opens search.** The first letter typed into the password (or username) box used to start a search over the Wi-Fi page; text fields now keep their own typing.

## 1.6.1 (2026-11-24)

- **The new battery look.** The battery in the menu bar, on the battery page, in quick info and in the charging animation now matches Apple's 2027 design: no outline, just a pale battery that the charge fills from the left.
- **Energy Mode in the battery stats.** The menu bar battery's stats now have the Low Power / Automatic / High Power switch from the notch's battery page, for the power source you're on.

## 1.6 (2026-11-24)

### Shazam in the notch

- **Name the song playing around you.** Press the new Shazam button in the controls, next to the battery, or pull Shazam in with two fingers sideways over the notch while nothing is showing.
- **Pulling it in feels physical.** The Shazam mark follows your fingers in from the side and pulls back against them, and a ring around it fills as you go. When you've pulled far enough, the ring closes and the trackpad clicks. Let go there and the mark lands with a small bounce and starts listening. Let go too soon and it springs back out, and nothing happens.
- **While it listens,** the mark pulses with ripples running out of it and a small equaliser dances on the other side. To stop it, drag up or down with two fingers: it follows your fingers and stops once you've dragged far enough, or click it.
- **When it finds the song,** the notch grows into a card. The mark flies into the cover's place, the cover lands on it, and the title and artist slide in.
  - Click the card to open the song in Apple Music.
  - Use the copy button for "Title – Artist", or hover the title or the artist and click to copy just that.
- **Saved to your Shazam history.** Songs it finds are added to your Shazam library, so they also show up in Shazam on your iPhone.
- **Microphone and network.** It asks for the microphone the first time and uses it only while listening. Only a short sound signature is sent to Shazam, never the recording. Because it listens through the microphone, it can't hear music playing through your headphones.
- **Turning it off:** Settings > Features > Shazam.

### Face Unlock

- **One Security choice:** Faster, Standard or More secure, instead of several modes and switches. Each tries the quietest check first: a model that tells a real face from a photo or screen, which unlocks you straight away when it's sure.
  - When it isn't sure, Standard briefly lights the screen.
  - More secure lights the screen more readily, and as a last resort asks for a random blink, smile or head turn.
  - Faster never lights the screen and asks for a blink instead.
  - Your old choice carries over to the nearest level.
- **The light check no longer depends on your wallpaper.** The screen glows white under the notch for about two seconds, so the scan stays visible. The glow's strength follows the room's light: soft in a dim room, using the XDR display's extra brightness in a bright one, and none when the room is too bright for it to matter.
- **The Match threshold slider is gone.** The Security level sets how closely your face has to match. Once it has learned from 20 unlocks, it tightens to just under your usual scores, up to 0.55 on Faster, 0.60 on Standard (as in 1.5) and 0.75 on More secure.
- **One learning switch.** "Learn from successful unlocks" and "Raise the threshold as it learns my face" are now one switch, "Learn my face from unlocks". The spoof model and lighting the screen in a dark room are always on.
- **Test recognition** shows the threshold in use, and what the scan would do with the spoof model's current score ("Unsure: would glow", "Fake: would doubt").
- **A real face the spoof model doubts can still unlock.** The model can take a real face for a photo, a hood round your face especially. On Standard and More secure that face is no longer refused straight away: the screen glows to check its shape and then you blink (or do the random challenge), both. If the glow doesn't vouch, it's refused as before; a photo or a screen doesn't answer the glow. In a room too bright for the glow, the model's "fake" no longer refuses at all and the blink is asked as soon as your face matches, as it already was with direct sun on your face. Faster still refuses it. The model also has to be sure for about 0.7 s before it refuses, not 0.2 s, so a face it wavers on isn't refused on every attempt.
- **The lock screen says what it's doing.** Instead of "Checking": "Recognizing you", "Making sure it's you", "Hold still: checking with light" during the glow, and in the sun or a very bright room "Bright environment detected, blink to unlock", asked as soon as your face matches instead of after trying the glow.
- **Simpler face setup, and a new look.** Instead of moving your head in a full circle: look straight ahead, then tilt your head up, down, left and right as the notch asks. A line-drawn face, like Face ID's, replaces the grid of dots: during setup it sits in a ring whose next quarter glows (brighter once you've turned far enough) and fills in when done; on the lock screen it breathes while looking, blinks when it wants a blink, and turns into a check when you're in. Your face is scanned the same way as before (the model looks at one photo at a time), just from 4 directions instead of 8, with 3 photos each.
- **Scan Again saves your new scan.** Re-enrolling (to add glasses, say) failed just as the circle closed with "Couldn't get a clear scan. Try better light": the light was fine, the new scan couldn't replace the old one in the Keychain. It's now updated in place, and if saving ever fails it says so. Learned looks are saved the same way.

### Notifications and Messages

- **Longer notifications.** They grow downward to fit their text, up to 6 lines in the bar and 10 on the hover card, so most can be read without hovering.
- **Messages in the notch is now a window onto Messages.** Conversations show read only, smoothly and live as messages arrive; one big Reply in Messages button opens the conversation there to answer. Replying, tapbacks and the emoji picker in the notch are gone, so Messages no longer has to come forward and nothing stutters. The back button always goes to the conversation list, and a notification's Reply button is now View. Dynamic Peninsula no longer asks to control Messages.
- **Contact photos in Messages.** The inbox and a conversation's header show the person's photo from Contacts, where they have one. Group chats keep their initial.
- **Connecting AirPods is left to macOS.** The notch no longer shows its own "Connected" when AirPods or another Bluetooth device connect: macOS already shows its card in the top-right corner, and it can't be moved away, so the notch only repeated it. Wi-Fi and Focus still show in the notch, and connecting a device from the panel works as before.

### The panel

- **Settings from behind the camera.** With the panel beside the notch, move the pointer behind the camera: the header fades and "Click to open Settings" appears across it. Click to open Settings. The gear is gone from there, and Shazam moved to the right side, so the battery no longer gets cut off.

### Wi-Fi and Bluetooth

- **Says when Location is the problem.** Without Location access macOS hides the network's name, and the notch used to say "Not connected" even though you were. It now says "Location needed" in quick info and on the Wi-Fi tile, and "Connected · name needs Location" in Wi-Fi's details, where the button to allow it is.
- **Your devices' own names.** AirPods and other devices show the name you gave them ("Marco's AirPods Pro"), as Bluetooth Settings does, instead of just the model.
- **Battery for AirPods and other devices.** Bluetooth's details show each connected device's charge: the earbuds and the case for AirPods, one battery for others. Quick info shows it next to the device's name. 20% and under is red.

### Fixes

- **No dark lines around the notch.** With the glass look, the closed notch no longer has dark lines around it.
- **Setup fits the screen.** The setup window can be resized, is never taller than the screen, and its feature list scrolls, so Continue is always in reach (with a larger text size the list ran past the bottom).
- **Shazam is steadier.** Stopping Shazam just as it found a song could crash Dynamic Peninsula; it no longer does. A slow network no longer holds the song back waiting for its cover. Locking the Mac or pausing Dynamic Peninsula stops Shazam, so the microphone isn't left listening behind the lock screen.
- **Messages keeps up.** The unread count no longer stops updating if Messages' history log was missing when Dynamic Peninsula started.
- **Conversations open without a hitch.** A conversation is read in the background before the panel switches to it, so the island keeps moving smoothly, even while the inbox is refreshing.
- **An unusual message can't crash it.** Message text is read by Dynamic Peninsula itself instead of by an old system decoder that crashed on anything it couldn't read.
- **No more log file.** The AirPods diagnostics file the test builds kept in Library/Logs is gone, and removed if it's there.
- **Battery stats icon click.** Clicking the menu bar battery while its stats are open now closes them instead of opening them again. Clicking elsewhere to close them, then clicking the icon, no longer opens them straight back up.

## 1.5 (2026-11-23)

### Islet is now Dynamic Peninsula

- It's not quite an island: it's joined to the top of the screen. The app, its menus, Settings and the release are now called Dynamic Peninsula. It's the same app underneath, so your permissions, Face Unlock, settings and updates carry on as they were.
- A new icon to match: a black peninsula as wide as the real notch, joined to the top edge of the screen, with a beach, shallows and surf, in a turquoise sea.
- Updating from 1.4 installs it as Islet.app; the update after that renames it to Dynamic Peninsula.app.

### Menu bar battery

- The menu bar icon can be a battery instead of the pill, so it can stand in for the macOS battery icon and not take up a second spot. Turn on "Battery in the menu bar" in Settings > Battery (or in the features list); Settings has a shortcut to Control Center settings, where you hide the macOS one.
- It draws like macOS's: the charge as a fill, a bolt while charging, a plug when plugged in and not charging, red at 10% and yellow in Low Power Mode, with the percentage beside it (can be turned off). The fill turns green while the battery is actually charging, so you can tell at a glance when a plugged-in Mac isn't.
- Click it for battery stats: time left or to full, time since unplugged, power source, cycle count, temperature, battery health, a chart of the last 12 hours, and a live diagram of where the power is flowing: from the battery, the charger or both into the Mac, and from the charger into the battery while it charges. The lines thicken and flow faster with more power. Or set the click to open the control center, as from the notch. Right-click still gives the app's menu.
- With a charge limit set, the stats say "Time to 85%" (timed to the limit, not to full) with the limit right under it.
- With the glass look on (macOS 26 and later), the stats are Liquid Glass like Control Center's, following System Settings' Liquid Glass and Reduce Transparency choices, with text that stays readable on light or dark glass.
- The chart starts full: the hours before the app was running come from macOS's power log. A day of charge history is kept on the Mac (Application Support/Islet); nothing leaves it.
- Live figures: the stats and the battery page update every second from the Mac's own power sensors (the battery's figures only change every 30 seconds or so), and the charger, Mac and battery numbers always add up.
- Charging shows at once: when a charger goes in or out, and when more power comes in than the Mac is using, it shows as charging even before the battery's own flag catches up (which could take a while and showed "Not Charging" with 50 W going in).
- Every battery in the app (the menu bar, quick info, the battery page and the charging animation) now has the same shape: a body twice as long as it is tall.

### Messages

- A messages pill shows next to the battery in the panel when you have unread messages, with the same count as Messages' badge: chats with unread messages from known senders. It reads Messages' own history, so reading on your iPhone clears it too, and replying from the notch clears that chat.
- Click it for an inbox: chats with new messages first, then your other recent ones. A conversation opened from it has a back button to the inbox.
- Photos and stickers show in conversations instead of "Attachment", including stickers placed on a message. Click a photo to open it.
- The Emoji & Symbols picker (⌃⌘Space or the smiley button) now opens in front of the panel instead of behind it.
- With the panel open, swiping up closes it only from the notch itself, so scrolling the inbox or a conversation doesn't close the panel.

### Volume and brightness

- Turning the volume or brightness while the unlock animation is playing (or on the lock screen, or during the face scan) now shows it: the island grows a row underneath with the level, instead of the change going unseen until the animation finished. When the unlock finishes first, the level's icon, bar and number glide up into the level's own place.

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

### Fixes

- The app no longer freezes at launch while macOS's Bluetooth permission prompt is waiting for an answer: it asks in the background and starts Bluetooth once you've answered.
- Macs without a notch: the island now answers the pointer at the top of the screen while you're on the desktop. macOS doesn't send pointer moves to other apps while the desktop is in front, so the app now also watches them another way.
- Search opens with ⌥Space by default, so it doesn't take ⌘Space from Spotlight. You can still give it ⌘Space in Settings > Search.
- Contacts permission: pressing Allow now asks for access. Before, the app was missing the Contacts entitlement its signing needs, so macOS refused silently and System Settings showed an empty Contacts list.
- Settings' sidebar shows the version on its own line under the name.
- After turning on a permission like Full Disk Access, System Settings' "Quit & Reopen" now brings the app back. It used to quit and stay closed.

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
