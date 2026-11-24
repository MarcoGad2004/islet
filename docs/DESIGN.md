# Islet v1 design (locked)

This is the source of truth for what v1 looks like and how it behaves. It was settled in a
design session on 2026-11-18 using an interactive mockup canvas:
<https://claude.ai/artifact/9gDTDbkfLsf2UXTDE6WJ8U> (private; open the "v1 locked" page, and play
the "v1 prototype" artboard to see the motion). The canvas is a web approximation: where it and
this file disagree, this file wins.


**Name (1.5, owner's decision 2026-11-23):** the app is called Dynamic Peninsula: everything the user reads says that.
"Islet" stays as the code's and the repo's name, and the bundle ID, so permissions and settings carry over.

## Scope

v1 has five features:

1. **Media**: now playing, with controls.
2. **Charging and battery**: charger connected, fully charged, low battery.
3. **Volume and brightness**: replaces the system volume/brightness display.
4. **Face unlock**: unlocks this Mac's lock screen with the built-in camera (convenience, not security).
5. **Unlock animation**: plays after any unlock (face, Touch ID, Apple Watch, password).

Not in v1: timer (macOS already does it), file shelf, calendar.

## The island

The island is always black (`#000`) and always attached to the top edge of the screen. It never
fades in or out; it only changes shape. It has three layouts.

### Top corners (added 2026-11-19, owner feedback)

Every shape's stem flares outward by 6 pt at the top edge (a small concave curve), like the real
notch, instead of meeting the top edge at a hard right angle.

### Wings

Content sits beside the camera, 60 pt to each side of the notch, inside the menu bar. The middle
notch-width area stays empty (camera).

- Size: notch width + 120 × notch height. Bottom corners 12.
- Used for: media, charging/battery, unlock animation.
- Only allowed when both sides have **60 pt + 8 pt margin** free of the front app's menus and of
  status icons (see "Menu bar width check").

### Chin

When the wings don't fit, a **stem** exactly the size of the notch runs through the menu bar and a
**body** hangs below it, over the desktop, so no menu or status icon is ever covered.

- Body: 300 × 36, directly under the stem. Corners: 16 all round (top and bottom equal, owner 2026-11-19).
- 10 pt concave curves join the stem to the body's top edge on both sides.
- Volume and brightness use the wide bar when wings fit (icon left, number right, the 16-step bar in a short body
  below, 20 pt side inset all round); they use the chin only when the menu bar has no room. Option + Shift with the
  keys adjusts in quarter steps (64 levels).

### Stem and body (large)

Used for the face scan and the expanded panel, regardless of the width check:

| Shape         | Size under the stem | Corners                              |
|---------------|---------------------|--------------------------------------|
| Face scan     | notch width × 150   | bottom 44, flush with the stem sides |
| Expanded      | 500 × 216           | top 16, bottom 30, 10 pt inner curves |

### Flush panel (1.4)

Owner approved, 2026-11-21 (layout A). Mockup: <https://claude.ai/artifact/TbJM4XJz5csFNQsX4dyYxQ> (source
docs/mockups/expanded-flush.html).

- **When**: in the notch, when the menu bar has room for the panel: on each side of the notch, (500 − notch width) / 2
  + 8 pt free of the front app's menus and of status icons (the same check as the wings). Decided as the panel opens
  and kept until it closes, so it never changes shape under the pointer. No room, no Accessibility, or no notch: the
  stem and body as before.
- **Shape**: no stem. The panel is 500 wide from the top edge down, its top corners flaring into the edge (6 pt,
  like every shape), bottom corners 30. It is the stem shape's height minus 44 pt: the header row moves up into the
  band beside the camera.
- **Header beside the camera** (on the Controls page and its detail pages): left, the battery chip, update and Focus
  icons (or the back button and the page's name on a detail page); right, the Shazam button, then the album art and
  play/pause when music is loaded (owner's request, 2026-11-23: Shazam moved right so the battery chip isn't cut off).
  The "Controls" label and the song's name aren't shown; hovering the art shows the name and clicking it opens the
  player. Everything else on the page moves up by the header's height.
- **Settings behind the camera** (owner's request, 2026-11-23): flush, there's no gear. With the pointer behind the
  camera the header row fades out (0.2 s) and "Click to open" (left of the camera, `secondary`) and "⚙ Settings" (right
  of it) fade in; a click there closes the panel and opens Settings. With the stem (no room beside the camera) or
  without a notch, the gear stays at the header's right end, with Shazam just left of it.
- **Other pages** (the player, search, a conversation, the notification list) keep their layout: the band beside the
  camera is part of the black panel, with the page under it.
- **Motion**: like the wings, the notch springs out sideways and down at once (width with the wings' soft overshoot,
  height ease-out), content fading in at ≈0.3 s. Closing pulls it back into the notch.

### All shapes

| Shape         | Size                              | Corners            |
|---------------|-----------------------------------|--------------------|
| Closed        | the notch (≈190 × 34, measured)   | bottom 10          |
| Hover peek    | notch + 16 wide, + 6 tall         | bottom 14          |
| Wings         | notch + 120 wide, notch height    | bottom 12          |
| Chin          | stem + 300 × 36 body              | 16 all round       |
| Face scan     | stem + notch-wide × 150 body      | bottom 44          |
| Expanded      | stem + 500 × 216 body             | top 16, bottom 30  |
| Quick info    | the wide bar, or stem + 340 × 60  | bottom 18 (chin top 16) |

Hover peek is the closed notch's hover shape. Over anything compact that is showing (wings, wide bar, chin), hover
swells it instead: 12 pt wider and 3 pt taller (the chin's body 14 × 4), bottom corners + 2, on a springy bubble
(0.32 s, damping 0.52). The swell rides on top of the shape's own motion on springs of its own, so it answers the
pointer at once even mid-morph (wings springing out, the chin dropping) and lets go the same way. The content scales
with the swell on the same spring (owner request, 2026-11-20), so its padding stays even. The panel, face scan
and enrolment don't swell; nor does the island in menu bar or bezel mode.

## Motion

### Flow down, then bubble out

Any change that puts a body below the stem:

1. The body flows straight down from behind the stem **at notch width** (0.34 s, ease-out).
2. From 0.2 s it bubbles out sideways to its full width with a soft overshoot (≈0.6 s spring).
3. Corners settle from 0.12 s; the inner curves fade in from 0.22 s.
4. Content fades in (opacity, plus scale from 96%) at ≈0.36 s, after the shape has mostly settled.

Going back up: content fades (0.12 s), then the island closes like the iPhone's island: it first
lands in a pill a little bigger than the notch (notch + 18 wide, + 6 tall, bottom radius + 4). The stem swells while the
body pulls in (0.18 s) just ahead of rising into it (0.26 s from 0.06 s), so the corners stay round throughout. Once the
body is gone the pill eases down to the notch (0.38 s, soft settle). Closing into the chin instead (from the expanded
panel) pulls the width in first, then rolls the body up.

Wings: width springs out with the same overshoot (0.55 s); content fades in after 0.12 s. Closing, the wings pull in
(0.3 s spring) to a pill 12 pt wider and 3 pt taller than the notch, which then eases down into it like the chin's
close; the content draws in toward the notch (scale 0.82) as it fades over 0.2 s.

SwiftUI starting point (tune by eye on the real display):
- phase 1 (top/height): `.spring(response: 0.32, dampingFraction: 1.0)`
- phase 2 (width): `.spring(response: 0.5, dampingFraction: 0.62)`, delayed 0.2 s

Draw the island as **one custom `Shape`** (stem + body + inner curves) whose dimensions are
`animatableData`, so every change is a continuous morph rather than a cross-fade of separate views.

### Small animations

- **Icon pop** (bolt, check): scale from 0 with overshoot, 0.4 s.
- **Level bars** (media): 3–4 green bars, height 5–14 pt, bouncing on a ≈1 s loop with staggered
  phases. If real audio level is available use it; otherwise the loop.
- **Paused**: bars ease flat and gray over 0.4 s, artwork dims to 50%.
- **Track change**: artwork cross-fades 0.3 s; the chin's title slides up out and the new one up in.
- **16-step bar**: each key press fills/empties one step with a quick ease (≈0.12 s).

### Lock-screen story (revised 2026-11-19, owner request)

On the lock screen the island sits in the **wings** with a **white closed padlock on the right**. The face
scan expands the wide bar **downward** (wings width × notch height + 150, bottom radius 40) so the padlock
stays visible. On a match the face turns into a check (0.35 s), then the check **flies to the left wing**
(spring, from 0.65 s) while the right-hand padlock opens and turns green (starting 0.1 s after the match).
At the same moment the tall shape folds up into the wide bar, which holds the green check (left) and the open
green padlock (right) for about 2 s, then folds back to the notch. The lock-screen bar (locked, scan top, hold, unlock) is 8 pt taller than the notch so each icon has equal
padding on all sides: padlock ~8-9 pt, check ~13 pt (the check is an exact 18 x 13 stroked shape). The
padlock and check sit toward the outer edge of their wings so the notch never covers them. Any other unlock (Touch ID, Apple Watch, password) plays the
same layout without the scan: padlock on the right opens, check pops in on the left. This replaces the
old "lock on the left, check on the right" wings layout below.

### Lock opens (unlock animation)

1. 0.0 s: white closed padlock appears (wings: left side; chin: centred).
2. 0.4 s: the padlock body dips about 1 pt; the shackle lifts ~2.5 pt and swings open about its
   right leg (≈28°), finishing ~1.15 s.
3. 0.8 s: the lock turns green (`#32D74B`); a green check pops in on the right (wings), or
   "Unlocked" fades in beside it (chin).
4. 1.8 s: folds back to the notch, or to whatever was showing before.

Leave headroom above the padlock so the lifted shackle is never clipped.

### Face enrolment (added 2026-11-19, owner request)

Started from Settings → Face unlock, after confirming with Touch ID/password and storing the login
password. The island flows down into a 380 × 214 body (`enrol` shape, same flow-down/bubble-out motion).

- **Ring** (owner's Option B, 2026-11-24, replacing 48 ticks, the dot grid and the head dot): one solid 4 pt ring,
  radius 58, `#2C2C2E`, in four quarters (right, up, left, down; 80° each with a gap). They're asked for one at a
  time, up, down, left, right (it was a full circle of 8): the quarter to do next shows cyan at 30%, 70% while the
  head is turned far enough that way, and fills cyan once three good face samples are captured there. Only the
  asked-for quarter captures. "Straight ahead" is calibrated from the first ~0.6 s (3 samples).
- **Face**: the line-drawn face (`FaceGlyph`: four corner brackets, two eyes, nose and smile, 3 pt lines, 92 pt)
  inside the ring: grey and breathing until a face is in view, then cyan; its features slide up to 10% of its size
  the way the head is turned.
- **Labels**: "Looking for you" → "Look straight ahead" → "Tilt your head up" → "Tilt your head down" → "Turn your
  head left" → "Turn your head right".
- **Done**: the features fade into a green check drawn in 0.35 s, ring and brackets turn green, "Face enrolled", fold
  back after 2.4 s. **Failure** (no consistent scan, the scan couldn't be saved, or 2 min): ring and face turn red,
  the face shakes, red label, fold back.
- Click and hover are ignored while it runs; Cancel is in Settings.

### Face scan

The scan shape flows down at notch width (no bubble-out; it stays notch-wide).

- **Looking** (owner, 2026-11-24, replacing the dot grid in a ring): the line-drawn face (`FaceGlyph`, 84 pt, no
  ring), `#48484A` and breathing (1.6 s) with no face in view, cyan (`#64D2FF`) once there is one, breathing while it
  recognizes and steady after; when the challenge is a blink its eyes blink every 1.6 s. Label: "Looking for you",
  then what it's doing (owner, 2026-11-24, replacing a generic "Checking"): "Recognizing you" once a face is in view,
  "Making sure it's you" while the spoof model's first frames come in, "Hold still: checking with light" during the
  glow, and the liveness challenge if one is needed (below): "Blink to unlock", or on More secure one of "Blink to
  unlock", "Smile to unlock", "Turn your head left", "Turn your head right", picked at random each attempt, with 8 s
  to do it. When it's asked because of the light (sun on the face, or a room too bright for the glow) it reads
  "Bright environment detected, blink to unlock" (and so on). One line, shrinking to 80% if it has to.
- **Security** (owner's design, 2026-11-23; replaces the Automatic / Random / Blink / Off modes, the spoof model
  switch and "just ask me to blink"): one choice of three. Each tries the quietest check first and goes further only
  when it isn't sure. The spoof model runs on every frame with a face from the start; once the face matches:

  | | Faster | Standard (default) | More secure |
  |---|---|---|---|
  | Spoof model unlocks at once at | ≥ 0.75 | ≥ 0.90 | ≥ 0.97 |
  | averaged over | 6 frames (~0.2 s) | 12 (~0.4 s) | 20 (~0.7 s) |
  | When it isn't sure | blink | glow, then blink | glow, then a random challenge |
  | Glow also needs the spoof model at | n/a | ≥ 0.5 | ≥ 0.75 |
  | Sure it's fake below (20 frames, ~0.7 s) | 0.25: refused | 0.25: glow and blink both | 0.35: glow and challenge both |
  | Match threshold until 20 unlocks are learned, and its floor after | 0.45 | 0.50 | 0.55 |
  | Once learned: under your usual scores (5th percentile) by | 0.08 | 0.05 | 0.02 |
  | Most the threshold can rise above its floor | 0.10 | 0.10 | 0.25 |

  When the spoof model is sure the face is fake, Faster refuses it; Standard and More secure doubt it instead (the
  model also calls real faces fake, a hood round the face for one; 2026-11-24): the glow has to vouch and then the
  challenge has to be done, and where the glow doesn't vouch it's refused. In a room too bright for the glow (over 1500
  lux, read as the scan starts), as with harsh light on the face, the model's "fake" doesn't refuse and the challenge is
  asked as soon as the face matches. There's no Off (owner, 2026-11-23: Faster is for convenience). The old modes carry over: Random to More secure,
  Off to Faster, the rest to Standard. The match threshold is set by the level too, not by hand (owner, 2026-11-23:
  the slider is gone); Test recognition shows the one in use and how it was set.
- **Light check** (Standard and More secure, when the spoof model isn't sure; owner request 2026-11-22): the label
  reads "Hold still: checking with light" while the screen lights the face. **Glow** (owner request 2026-11-23, replacing the brightness swell, which
  depended on the wallpaper being bright): after a random 0.3-0.45 s wait, a full-screen layer of white on the
  built-in display fades in over 0.3 s, holds 0.28 s, then takes four steps between a lower and a higher level in a
  random order (at least two up, one down; 0.15 s eased step, 0.28 s hold each), and fades out over 0.3 s: ~2.3 s
  in all, never more than one change every 0.43 s, every edge eased, so it breathes rather than flashes (the owner was
  worried about discomfort). It sits just under the island, over everything else including the lock screen and its
  password field, so the island and its scan stay visible on top. Its strength follows the room (the ambient light
  sensor): the higher level is 0.08 + lux / 2000 of the panel's peak (at most 0.65), the lower one at least SDR white
  and 1.6× under the higher, using the XDR panel's extra brightness when it's needed; a dim room gets a gentle glow, a
  bright one a strong one. Where the glow can't be drawn, the brightness swells once instead (up 0.3, or down if the
  screen is above 0.7, over 0.25 s, held 0.35 s, back over 0.3 s). If the light check vouches and the spoof model
  is at least at the level's floor, it's the match with nothing to do; otherwise the level's challenge is asked.
  It's judged as soon as its last step has held (the light still fades out afterwards). **Harsh light** (owner
  request 2026-11-23): when the camera sees direct sun on the face (one side ≥ 3× brighter than the other, or ≥ 6% of
  the face blown out), or the light sensor reads over 1500 lux, there's no glow: the challenge is asked as soon as the
  face matches. The same for the rest of the scan once a glow got no response.
- **Dark room** (always on since 1.6): if the camera sees a dark room, the screen brightness eases up over ≈1.4 s to light the
  face, and eases back over ≈1 s when the scan ends. Pressing a brightness key cancels it.
- **Match**: the features fade and a green check draws in (0.35 s), the brackets turn green; label "Welcome back". After ≈0.9 s the shape pulls up and
  the **lock opens** animation plays.
- **No match**: the face turns red (`#FF453A`) and shakes sideways (0.45 s), label "Not
  recognized". After 3 failed tries, stop and wait for Command+Shift (below).
- **No face in view**: no face in front of the camera for 10 s: label "No face in view" (failed style),
  fold back after 1.6 s and wait for Command+Shift.

### When the scan starts (1.1.3, owner request)

- **Display wakes on a locked Mac** (lid opened, display woken after it slept, screen saver dismissed): scan
  at once.
- **Locked with the display on** (power button, Ctrl-Cmd-Q, Apple menu → Lock Screen): don't scan, so the Mac
  doesn't unlock straight back. Wait for **Command+Shift** (Shift alone types capitals in the password).
- After a scan gives up (no face, 3 misses, 60 s), it also waits for Command+Shift.
- Any display sleep clears the wait, so the next wake scans at once. Command+Shift always starts a fresh scan
  (3 new tries) whenever the Mac is locked, the display is on and no scan is running.
- **Hint** while waiting: "⌘⇧" (13 pt semibold, secondary grey) in the left wing of the lock bar, 8.5 pt from the
  island's left edge (the same gap the padlock keeps on the right). After 1.5 s the bar grows a 28 pt body (bottom radius 18, like the volume bar) reading "Press ⌘ + ⇧ to
  use Face Unlock" (12 pt semibold, white) for 4 s, folds back, and repeats every 12 s while it waits. The
  wing glyph hides while the sentence shows. Preview: `-IsletDebugShape lockhint`.

## Features

### Media

- Shows while anything is playing; hides 30 s after pause.
- **Wings**: artwork (22 pt, radius 6) on the left; level bars on the right.
- **Chin**: artwork, "Title · Artist" centred (scrolls if long), level bars.
- **Hover (wings)** (owner, 2026-11-20): hovering media in the wings turns it into the volume/brightness wide bar: the
  artwork and app icon stay in the wings and "Title · Artist" (12 pt) shows in the 26 pt body below. Only the name fades
  in; the wings' content doesn't remount. The chin already shows the name, so it just swells as before.
- **Media peek** (owner, 2026-11-20; replaces the 4 pt green dot): media swiped away, pointer over the notch (notch mode
  only). The peek shows only that something is playing, in the album's colours: three colours taken across the artwork,
  left to right, livened a touch (`ArtworkPalette`). With the glass look the glass strip's glow takes those colours
  (stronger, 90%); without it a 64 x 2 pt line glows just under the camera, slowly breathing. Swiping down from the peek,
  the colour gathers into the artwork's place in the wings or chin over 0.5 s, sharpening into the cover; the real
  artwork shows once it's there. Mockups: <https://claude.ai/artifact/GSgkioHQ86nzvjaZdJA8jo>.
- **Skip and previous** (owner, 2026-11-20): a two-finger swipe left (next) or right (previous) over media, on the
  wings, the wide bar, the chin or the peek.
  - In the wings it is always the wide bar while the swipe lasts. The name rolls in the body (or the chin's middle): the
    current name out the way the fingers go, "Next song" / "Previous song" in from the other side (the player only names
    the new song once it plays). Skip plays in the right wing, where the app icon shrinks away; previous in the left,
    where the artwork does. The icon is three triangles (two showing) that lean with the fingers; when the song changes
    they push one step forward.
  - On the peek the colour stays put: the peek deepens up to 18 pt and the icon is pulled in from that side under the
    camera. The colour changes with the song.
  - The fingers drive it directly, against resistance (owner, 2026-11-20: "you have to pull them in and out"): progress
    = 1 - 1 / (1 + travel / 95 pt), so it trails the fingers more the further it goes and the commit point (half way)
    takes 95 pt. The icon sits in a ring that fills as you pull; at the line it turns into a solid white disc with the
    icon in black (with a pop and a trackpad tap). Only that counts: let go before it and it always springs back, however
    fast the fingers were going (owner, 2026-11-20). The names sit 110 pt apart in the wide bar, 100 in the chin. Half way lights the icon and taps the
    trackpad. The lift comes from the scroll event's phase (momentum never counts), and a spring takes over from where
    the fingers left it at their speed through the resistance: past the line,
    the command goes at once and it lands (response 0.18-0.34 s by speed, damping 0.8); otherwise it snaps back out with
    a little elastic overshoot (0.3 s, damping 0.7).
    After landing the new name fades in over 0.24 s and the slot hands back from 0.33 s.
- **Expanded (media playing)**: media only. Header "NOW PLAYING" and a collapse chevron. Artwork
  80 pt (radius 14), title (17 semibold), artist, album, previous / play-pause / next on the right,
  then a draggable scrubber with elapsed and total time. Clicking the artwork brings the playing
  app forward.

### Charging and battery

Short events; each shows, then hands back to what was showing.

| Event                | Duration | Wings                          | Chin                                     |
|----------------------|----------|--------------------------------|------------------------------------------|
| Charger connected    | 3 s      | green battery with bolt, green % | battery, "Charging · 1:10 to full", %  |
| Fully charged        | 3 s      | full green battery with bolt, "100%" | same with label                    |
| Low battery 20%, 10% | 4 s      | red battery, red % (`#FF6961`) | red battery, "Low battery", red %        |
| Charger removed      | none     | -                              | -                                        |

"Fully charged" also fires at the charge limit if one is set. Low battery only fires when not charging.

Motion (1.4, owner request 2026-11-21, mockup `docs/mockups/charging.html`), timed from the event appearing:
- The battery (13 pt tall, the shared battery shape: see "Menu bar battery") fades in empty. The percentage drifts up 5 pt into place, growing from
  80% and sharpening out of a 2.5 pt blur (0.1 s, over 0.45 s).
- From 0.15 s to 0.85 s the percentage rolls from 0 to the charge like an odometer (each digit a column that scrolls,
  fading at its top and bottom edges) and the fill grows with it. It eases in, then eases out as it lands.
- The bolt (white with a black outline, a little taller than the battery, centred on its body) springs in from 0.45 s
  (response 0.4 s, damping 0.62, about 8% overshoot and a 12° twist straightening) so it settles at 0.85 s as the fill
  stops. Fully charged rolls to 100%.
- As they land (0.85 s), the battery and the percentage both give a small springy bounce: about 6% bigger, then back
  to their size within half a second.
- Low battery starts full and rolls down to the charge, draining, in red, with no bolt.
- With Reduce Motion it shows the end state at once.

### Menu bar battery (1.5)

Owner request, 2026-11-23. Islet's menu bar icon can be the pill (default) or a battery: "Battery in the menu bar", a
feature of its own (off by default; Features list and Settings > Battery > Menu Bar, with its click, percentage and
the link to hide macOS's), so one icon can do the job of macOS's battery and Islet's. As a battery it always shows, whatever "Show menu bar
icon" says, and works the same with a notch, the bezel island, the menu bar island, or none.

- One battery shape everywhere (`BatteryMetrics`): the menu bar icon, the battery page (22 pt tall), quick info
  (12 or 13 pt) and the charging animation (13 pt) differ only in height. The body is twice as long as it is tall,
  with the gap, nub and corners as fixed shares of that height.
- Since 1.6.1 it follows Apple's 2027 battery (owner request, 2026-11-24): no outline. The body is a solid pale track
  (40%) and the charge fills it from the left edge to edge, clipped to the body's rounded corners, its right end cut
  straight; at least a sliver shows above 0%. The nub is pale too, flat against the body and round on the outside.
- The icon follows macOS's: a 31 × 15 pt battery (27 × 13.5 pt body) with 3 pt of clear space either side (1.6.1) so it doesn't crowd the icons beside it, the pale track, the charge as a solid fill, a bolt while
  charging and a plug when plugged in and not charging (each with a smooth 1 pt gap cut round it so it reads over the fill and the track). Green
  fill while the battery is actually charging (back to the menu bar's colour once it stops, even still plugged in; the track, the nub and the
  bolt stay the menu bar's colour), red fill at 10% and below on battery, yellow in Low Power Mode; otherwise a template image in the menu bar's colour.
  The percentage sits to its left unless "Show percentage" is off.
- Click: "Battery stats" (default) or "Control center" (Settings). Right-click or Control/Option-click: Islet's menu.
- The stats drop down 5 pt under the icon, left edges lined up and kept 8 pt inside the screen: a 300 pt panel: with the glass look (macOS 26 and later) Liquid Glass like Control Center's (24 pt corners, the system's own glass as it comes (light or dark with the Mac's appearance, no tint of ours), so it follows System Settings' Liquid Glass and Reduce Transparency choices, with the text in the system's adaptive label colours (`IsletInk`) so it stays readable on it; clipped to its rounded shape with no window shadow, so nothing square shows round it; glass tiles and pills inside), otherwise dark glass
  panel (HUD material, 14 pt corners) with, in order: "Battery" and the percentage; time left (or to full, or "Time to 85%"
  with a charge limit, timed to the limit, or the status), the charge limit right under it when there is one, and
  time since unplugged; then, on a Mac with energy modes, "Energy Mode" with "On battery" or "On power adapter" on the right and, under it, the battery page's Low Power / Automatic / High Power switch at full width (1.6.1, owner request, 2026-11-24; it changes the mode for the source in use, and a failure shows under it in red); a rule; power source (with the charger's name), cycle count, temperature (°F or °C by
  region), battery health (System Settings' maximum capacity), and Low Power Mode when it's on (only on a Mac without energy modes, where the switch above can't show it); a rule; "Last 12 hours", a green line over a fading green fill, 0/50/100% on the right, every 3 hours along
  the bottom; a rule; "Power distribution", a flow diagram: Charger, Mac and Battery as round glass nodes in a row
  with their watts under them, a line from the charger into the Mac, one from the battery into the Mac, and an arc
  from the charger over the Mac into the battery. A line runs only while power moves along it (faint rails
  otherwise), thicker for a bigger share, with dashes drifting the way the power goes: green from the charger,
  yellow from the battery. So it shows battery only, charger only, charger charging the battery, and a charger too
  weak for the load with the battery helping. The dashes run faster with more power (8 pt/s barely moving to 30 pt/s at 100 W, on a square root),
  easing to a new speed over about a second without jumping. Changes glide (spring, 0.7 s): a line lighting up runs out from its
  source, one going dark draws back and fades, thickness and colours ease. The battery's share is the charger's input
  minus the Mac's draw, rounded alike, so the labels always add up. Still dashes with Reduce Motion; a rule; a "Controls" pill that opens the island's control center and "Battery Settings…".
  Numbers refresh every second while open, and at once when a charger goes in or out. A click elsewhere, Esc or the icon closes it.
- In menu bar island mode the icon's click is the one setting decides; with stats, the island opens from the panel's
  Controls pill.
- Charge history: a sample on every change of charge or charger and every 5 minutes, a day kept in Application
  Support; the time Islet wasn't running is filled from `pmset -g log` (RESEARCH.md "Battery stats").

### Volume and brightness

- Shows on volume, mute and brightness keys. Hides 1.5 s after the last press.
- Always the chin: icon (speaker or sun), a 16-step bar (steps 9 × 6 pt, 3 pt gaps, on
  `#F5F5F7`, off `#3A3A3C`), the value 0–100 on the right. Both use the same white.
- Muted: speaker with a cross, bar dims (on `#636366`, off `#2C2C2E`) but keeps the level, value "Off".
- Motion: the fill glides across the steps on a spring (response 0.32, damping 0.82) rather than steps
  snapping, the number's digits roll up or down to the new value, and the speaker icon swaps with a
  symbol transition. The Control Center sliders and their percentages do the same for key presses
  (a drag follows the pointer directly).
- Clicking it opens the expanded panel's Display and Sound page, even while media plays.
- **Extended brightness** (1.7, owner request 2026-11-24; built-in XDR panels only): at 100, holding brightness-up for
  1 s goes past it. The number counts on past 100 (up to 160), and a second fill in red (`isletRed`) runs over the
  white steps from the left edge on the same scale, so 160 fills to the 60 mark (9.6 steps). Each further press adds
  a step (1/16, or 1/64 with Option + Shift); the press that unlocked it doesn't keep climbing while held. Brightness-down
  takes the red off first, step by step, and at 100 it's off; then the white bar drops as usual. Moving the brightness
  slider also turns it off. It turns itself off when the screen sleeps or locks, the lid closes or the display
  changes, below 20% battery on battery power, or at serious thermal pressure, and it never survives a restart.
  Settings > Notch > Brightness has its switch (on by default, shown only on an XDR Mac).
  - **Nudge** (owner, 2026-11-24): reaching 100 with brightness-up, the bar gives a small bump against its end (scale
    1.04 from the left and back), and 0.7 s later "Hold ☀ for XDR brightness" ("XDR" in red) cross-fades into the
    bar's place; the level then stays 2.8 s instead of 1.5 s. A tap at 100 that lets go too soon brings the hint
    back after 0.25 s.
  - **Hold**: with the key held at 100, after 0.15 s (so a tap doesn't flash it) translucent red fills the whole bar
    from the left over the rest of the second, and the sun swells (up to 1.22×) with a red glow. Let go early and the
    fill drains over 0.25 s and the sun settles.
  - **Unlock**: the bar flashes red and fades over 0.55 s as the first red step springs in, the sun bounces and the
    number rolls to 106.
  - **Controls and Display page**: the brightness slider shows the extra in red over the white fill on the same scale
    and its number counts past 100 %, with a red "XDR" label beside it. The Display page adds a card under the slider
    (the page grows 80 pt; the card is 70 pt tall so its text gets three lines): "XDR brightness is on", that it uses more battery and makes the Mac warmer and when it
    turns itself off, and Turn Off (back to 100). The keys' level HUD keeps only the red bar and the number.
- Under something that outranks it (1.5, owner request 2026-11-23): during the unlock animation, on the lock screen or
  during the face scan, a key press no longer goes unseen. The island grows a 34 pt row under what's showing, with
  the icon, the step bar and the number, and draws it back up 1.5 s after the last press. Under the wide bar it's
  the wide bar's width; under the chin, the chin's.

### Expanded panel

One page, no tabs. Opened by clicking the island.

- **Media playing**: media only (see Media).
- **Nothing playing**: the Control Center page (see below).
- Closes 1 s after the pointer leaves, on a click outside, on Esc, or on a two-finger swipe up.

### Control Center page (planned for v1.1, owner request 2026-11-19)
Replaces the Display and Sound page. Same 500 x 216 panel, nothing grows; the battery block and tall sliders give
up their space.

```
DISPLAY & SOUND           ⚡85% ☾  [♪ Song title  ▶]  ⚙
[ Wi-Fi ][ Bluetooth ][ AirDrop ][ Mirroring ]    4 tiles, about 110 x 58 pt: icon, name, status line
[ ☀ ━━━●━━━ 38% ]        [ 🔊 ━━●━━━━ MacBook Pro S… ]     two condensed sliders, half width each
```

- **Battery** is a chip in the header (bolt/percent; "Plugged in" on hover). No tile. Clicking it opens the battery
  page (1.3, owner request 2026-11-20): the body grows to 264 pt; a drawn battery (green charging, red at 20% or less
  on battery, bolt while plugged in), the percentage and what it's doing ("Charging · 1h 20m until full"), a Low Power
  badge when it's on; four glass stat tiles: maximum capacity and condition exactly as System Settings shows them
  (read from `system_profiler` on open; macOS's figure isn't a ratio in the registry, so full-charge vs design
  capacity is only the fallback), cycle count (of the design count), the charger's watts or the Mac's power draw, and a last tile that never repeats
  the one beside it: time to full / left (macOS's estimate, or energy left over the power flowing, "At this rate"),
  else what the Mac draws from the charger, else the energy stored in Wh; then the charge in mAh and a Battery Settings… button. With a charge limit set in System Settings
  (read from powerd's world-readable policy file), a "Limit 85%" pill opens Battery settings, the drawn battery has a
  tick at the limit, charging is timed to the limit ("Until 85%"), and at the limit the tile says "Charged · Holding at
  limit". Islet can't change the limit itself: only System Settings can (a private, entitled call; no Shortcuts action
  either). Under the tiles, an Energy Mode switch (Low Power / Automatic / High Power) for the source in use (`-c`
  on the adapter, `-b` on battery); the body is 308 pt with it. Changing it needs root; owner's decision
  (2026-11-20): the first change shows the macOS admin prompt and installs `/etc/sudoers.d/islet-powermode`, allowing
  only `pmset -b|-c powermode 0|1|2` for this account without a password; Settings > General has Remove…. The Low
  Power badge is gone (the switch shows it). Numbers refresh every second while it's open. Temperature isn't shown: the battery doesn't report it.
- **Focus** is read-only: an icon next to the battery chip showing the active Focus (hidden when none). It reads Focus
  state from the Do Not Disturb database, so onboarding asks for Full Disk Access. No Focus tile, no setting from the notch.
- **Update pill** (1.2.3): when an automatic check finds a new version, a blue "Update x.y.z" pill sits right of the
  battery chip (just the icon while the mini player is in the header). Clicking it closes the panel and runs the
  update with its progress in the notch. Nothing installs without that click.
- **Tiles** mimic Control Center: tapping the round icon toggles (Wi-Fi on/off, Bluetooth on/off); tapping the rest of
  the tile opens its detail in place. The AirDrop tile is the exception: it only shows the receiving mode (No One,
  Contacts, Everyone) and opens Finder's AirDrop window, because the mode cannot be changed without restarting sharingd.
  - Wi-Fi detail: on/off, the connected network (always first, with a Disconnect button), nearby networks (join; saved networks join directly; password
    prompt for new secured ones, username and password for Enterprise ones), a link to Wi-Fi settings. A Personal
    Hotspot shows as one: the tile reads "Hotspot" with the hotspot icon, the network gets a green "Hotspot" tag.
  - Bluetooth detail: on/off and only the accessories one connects on purpose (headphones, speakers, keyboards, mice,
    controllers; not phones, tablets, watches or Macs), tap to connect or disconnect, a link to Bluetooth settings.
  - Mirroring detail: available displays and AirPlay targets where reachable, otherwise it opens the system picker.
- **Sliders** stay draggable when condensed. A tap that does not move the slider (or its chevron) expands the card
  to fill the body; a back chevron returns. Drags never expand.
  - Display detail: large brightness slider, Dark Mode, Night Shift, True Tone (keyboard backlight if available).
  - Sound detail: large volume slider and the output device list (MacBook Speakers, Bluetooth headphones, ...),
    tap to switch.
- **Event animations** use the charger treatment (wings when the menu bar has room, otherwise the chin; icon pops in,
  text, 2.5 s, hands back to media): Focus turned on or off (icon and mode name), Wi-Fi connected (name of the
  network). Joining a Personal Hotspot instead uses the
  volume treatment: the wide bar (hotspot icon left, cellular bars right, both green) with the phone's name in the
  short body under it, or the chin when the menu bar has no room. A join started in the panel that is still going
  when the panel closes shows the same way, live: the network's icon pulsing on the left, a spinner on the right,
  the step in the body; then a check and "Connected to …" (2.5 s) or a cross and the error in red (4 s). The system's own banners for these are
  not hidden by the app (see RESEARCH.md Q22); the owner can turn them off in System Settings. A Bluetooth
  device connecting (AirPods and the like) shows no event: macOS shows its own "Connected" card, which can't be hidden
  (it's put back every frame when moved), so the notch only repeated it (owner, 2026-11-24; it was an event until 1.6).
- **Glide between pages:** the expanded panel is one stage. Every element (the two sliders, the tiles and their detail
  cards, the media artwork and title) is always present and has a rectangle for each page, so changing page moves it there
  with a spring (response 0.46, damping 0.72, the same family as the notch bubble); inner content cross-fades. The mini
  player's artwork and title grow into the Now Playing page. Mirroring lists Sidecar iPads (SidecarCore) and connects
  them; AirPlay targets (TVs) stay in Display Settings.
- **Audio source icon:** the right wing and chin of the media content show the playing app's icon (dimmed when paused)
  instead of level bars; the Now Playing page shows it beside the gear.
- Wi-Fi and Bluetooth details make the panel taller (216 to 300 pt) and it bubbles to the new size with a soft overshoot (the
  hover-bubble spring family); every other page keeps 216 pt. Lists scroll inside the panel. The Now Playing page has the
  same header as the details (back arrow to the controls, gear). The same hover bubble, morph and fade timings apply.
- Any tile whose native control fails on a macOS version falls back to opening its System Settings pane, so a tile
  never becomes a dead button.
- The system Control Center icon cannot be removed by an app: the owner hides it in System Settings > Control Center
  (onboarding explains how).

### Face unlock

Convenience, explicitly weaker than Touch ID. Agreed by the owner.

- Only unlocks **this Mac's lock screen**. Never used for sudo, Keychain prompts, App Store, System
  Settings or anything else.
- After a restart the password is still needed (FileVault unlocks the disk before any app runs).
- Flow: screen locked → camera checks for a face → on a match, the app types the user's login
  password (stored in the Keychain) into the lock screen → unlock animation.
- 3 attempts per lock, then stop.
- Only the Mac's built-in camera is used (never Continuity Camera, USB or virtual cameras).
- Spoof checks on every scan: a rectangle edge around the face, and a spoof model (MiniFASNet) that refuses
  a face it's sure is a print or screen (on Standard and More secure, that face needs the glow and the challenge
  both instead), and the Security level's light check and challenge (Face scan, above).
- "Learn my face from unlocks" (on by default; since 1.6 one switch for what were two): adds new looks, learns how
  the face answers the glow, and after 20 confirmed unlocks fits the threshold to just under the owner's usual
  scores, as the Security level sets (table above). With it off, the threshold is the level's starting point.
- Setup in Settings: confirm with Touch ID or the password, look at the camera to enrol, then enter
  the login password to store in the Keychain. Face data and the password never leave the Mac.
- Feasibility is **unproven**: see `docs/RESEARCH.md`. Build the spike before any UI.

### Unlock animation

Plays when macOS reports the screen unlocked (whatever unlocked it). See "Lock opens".

## Behaviour

### Priority

Face scan > lock opens > volume/brightness > FaceTime ringing > notification > Shazam (1.6) > charging/battery > media (1.4). Short
events cover media and hand back when they end. A FaceTime call in progress takes media's place.

### Gestures

With the pointer over the island:

- **Two-finger swipe up**: hides what is showing. Media stays hidden until swiped back or a
  different app starts playing. Short events (volume, charging, unlock) still appear. On the open
  panel, swipe up closes it.
- **Two-finger swipe down**: brings hidden media back; with nothing hidden, opens the panel.
- **Two-finger swipe left / right** over media: next / previous track (see Media, "Skip and previous"). Over the
  idle notch (quick info or the peek), either way: pulls Shazam in (see "Shazam").
- When media is hidden, hovering the notch shows the media peek (see Media).
- Media from the app in front stays out of the notch (you're already in the player) and comes back when you
  switch away. The panel's media page still has it.
- Click: opens the panel (Display and Sound if a level bar was showing).
- **Over a list in the panel** (a conversation, notifications, Wi-Fi, Bluetooth; owner, 2026-11-20): two fingers scroll
  the list and never close the panel mid-scroll. A swipe up closes it only as a fresh gesture that starts outside the
  list (the header, the reply field) or over a list that can't scroll that way any more (at the newest message, the end
  of the list); a scroll that reaches the end rubber-bands, and closing takes lifting and swiping again. The coast after
  the fingers lift never counts. Sideways swipes do nothing in the panel. The collapse arrow, a click outside and Esc
  always close it.

### Menu bar width check

- Front app's menus: read with the Accessibility API (menu bar of the frontmost app, each item's
  frame). Free space on the left = notch left edge − right edge of the last menu item.
- Status icons: read window bounds of other apps' status-item windows in the menu bar. Free space
  on the right = left edge of the nearest icon − notch right edge.
- Wings only when both sides ≥ 68 pt. Re-check on app switch, menu changes and display changes.
- No Accessibility permission, or the check fails: always use the chin.

## Notifications (1.4)

Owner approved, 2026-11-20. Mockup (playable): <https://claude.ai/artifact/7xTcPWs9qJyVJhFiUe5jWJ>. Feasibility:
RESEARCH.md Q27-Q31.

Calls and iPhone Live Activities in the notch were tried and dropped (owner, 2026-11-21): a call's banner
stays macOS's own, and Live Activities stay in the menu bar, where macOS can't be made to hide its copy.

### Notifications

Revised 2026-11-20 (owner): wings / chin like the other compact content, stacking, and the banner's own buttons.
Mockups: the "Wings, chin and stacking" prototype on <https://claude.ai/artifact/7xTcPWs9qJyVJhFiUe5jWJ>.

- **Source**: every banner macOS shows (read through Accessibility from Notification Center's banner window). Whatever a
  Focus or the app's own settings silence never makes a banner, so it never reaches the notch either. Alerts (the kind
  that stay until answered) are left to macOS.
- **The system banner is hidden**: its window is moved off screen the moment it appears and left there, so it still
  lands in Notification Center's list. Only banner windows are touched; Notification Center opened by the user is never
  affected. Incoming-call banners are never hidden.
- **Compact** (follows the menu bar width check, like volume):
  - **Wide bar** when the wings fit: wings plus a 26 pt body (bottom 18). The app icon (22 pt) in the left wing;
    "**Title** · message" (12; title semibold, message `secondary`, cut with an ellipsis) in the body, 20 pt in from
    each side. The subtitle, when there is one, leads the message ("Subtitle · Body").
  - **Chin** otherwise: the 300 x 36 body with the icon (20 pt), "**Title** · message" (13) and, on the right, the stack
    count.
- **Grows with the text** (owner, 2026-11-23): the wide bar's body and the chin grow downward to wrap the whole
  message, up to 6 lines; the hover card up to 10. The shape animates between heights as notifications change.
- **Card** (hover): the compact shape grows into the 360 x 72 card under the stem (top 16, bottom 20, 10 pt inner
  curves): icon 34 pt (radius 9), the title (13 semibold) with "now" (11, `tertiary`) on the right, and "App · message"
  (12, `secondary`, one line). Leaving folds it back.
- **Time sensitive** (the banner has the header "TIME SENSITIVE"): the card says "Time Sensitive" (11 semibold, orange
  `#FF9F0A`) instead of "now".
- **From the iPhone** (the banner ends "from iPhone"; the app usually isn't on the Mac, so there's no icon to look up):
  a grey rounded square with an iPhone glyph stands in for the icon.
- **The banner's buttons** (Duo's Approve / Deny, Slack's Remind Me…): never in the compact shapes, so a stray click
  can't approve anything. The card grows 36 pt and shows them as 28 pt pills on the right under the text, the last one
  white with black text (it's the app's main action); more than two go under an "Options" menu pill. A list row shows
  them once it's open (28 pt). Pressing one presses the banner's own button and takes the notification away.
- **Timing**: everything showing goes 5 s after the last arrival, then the island folds back to what was showing.
  Hovering pauses it; leaving gives it 3 s more.
- **Stacking** (several arrive close together, newest on top):
  - One: as above.
  - Two: the shape grows 8 pt deeper and a 3 pt strip (`#3A3A3C`, 64 pt narrower than the shape, 7 pt above its bottom)
    shows the second one tucked under it. The text changes to the newest.
  - Three or more: also "N more" (11 semibold, `secondary`) in the right wing, or at the right of the chin.
  - The card has a count badge on its icon (16 pt, `#3A3A3C`, 2 pt black ring).
- **Click**: opens the newest in its app (the banner's own Show); the next one moves up.
- **Two-finger swipe up**: dismisses them all.
- **In the panel** (owner, 2026-11-21: notifications used to take the whole panel, so the controls were out of reach
  while one showed): the panel always opens on its usual page (controls, music or the call), however it's opened.
  While notifications are waiting, a pill sits at the top of the page, 16 pt in from the sides, 12 pt from the top:
  32 tall, the panel's glass card shape (radius 16), the newest one's app icon (20 pt), "**Title** · message" (12;
  title semibold, message `secondary`, one line) and, on the right, the count when there are two or more ("3") and a
  chevron (`tertiary`). The page moves down by the pill's 44 pt and the panel grows to fit. The pill stays while the
  panel is open (the countdown is paused then); closed without using it, the notifications time out as usual and stay
  in Notification Center.
- **The list**: clicking the pill opens it on the panel (500 wide, as tall as the rows need: 52 pt each, at most 4
  showing, then it scrolls): a back chevron, "JUST NOW · N" and a "Clear all" pill on top; each row the icon (28),
  title and "App · now", the message (one line) and a close button. Clicking a row opens it in place (owner,
  2026-11-21): it grows to the whole message (up to 6 lines) on a soft highlight (white 8%), with its buttons under it
  on the right: the banner's own, then Reply for Messages or Open (white when it's the only one). Open opens it in its
  app (the banner's own Show) and closes the panel so the app shows; Reply opens the conversation in the panel.
  Clicking the open row again, or another row, closes it. The chevron,
  or the list emptying, goes back to the page it came from; a swipe up, a click outside or the pointer leaving for
  1 s close the panel as usual, and whatever is left stays in Notification Center.
- **Two-finger swipe down** over a notification: opens the panel with the pill, like a click on the closed notch.
- **Priority**: below volume and brightness and a ringing call, above connection notices, charging and media (see
  "Priority"). Not on the lock screen, nor while another panel page is open: then macOS shows the banner as usual.
- **Settings > General**: "Show notifications in the notch" (on by default; off leaves the system banners alone)
  and "Hide message text" (only the app and title).

### Messages (1.5)

Owner approved, 2026-11-20. Mockup: the "Messages in the notch" prototype on
<https://claude.ai/artifact/7xTcPWs9qJyVJhFiUe5jWJ>. Feasibility: RESEARCH.md Q32-Q38.

- **Arriving**: a Messages notification shows like any other (wide bar or chin); in a group, the message reads
  "Name: text".
Simplified 2026-11-23 (owner's decision: stability over features): the notch is a window onto Messages. It shows
conversations read only; replying happens in Messages. Sending, tapbacks, the emoji picker and marking chats read
(which all had to drive Messages) are gone, and so is the Automation permission for Messages.

- **Card**: Mark as Read (the banner's own) and **View**, white (Islet's own).
- **Click or View**: opens the conversation in the panel instead of the Messages app (Settings > General "Open
  Messages conversations in the notch", on by default; off, it opens Messages). It's found in Messages' history by the
  notification's text; if it can't be, Messages opens as before.
- **Conversation page** (500 x 300 under the stem): a header with a round back button (to the inbox, wherever the
  conversation was opened from), a 32 pt round picture (the person's Contacts photo in a one-to-one chat, else an
  initial on a colour per conversation), the name (14 semibold; contact names from Contacts, else the number; a group's
  own name, else its people's names) and "iMessage" / "Text Message" / "4 people · iMessage" (11, `tertiary`). Then the
  latest 50 messages, newest at the bottom: theirs on `#2C2C2E`, yours blue `#0A84FF` (iMessage) or green (SMS / RCS,
  bubble by bubble, as each message went), 13 pt in 16 pt-round bubbles up to 300 wide; a time between messages more
  than an hour apart (10, `tertiary`); in groups the sender's name over their first message in a run. Edits are left
  out. Tapbacks sit on the bubble's top corner like Messages (one of each emoji in a small dark pill, yours on a blue
  circle). Under your last message: "Sent", "Delivered", "Read 2:31 PM" (or "Read Yesterday", a weekday, a date) when
  they share read receipts, or, in red, "Not delivered".
- **Reply in Messages**: where the reply field was, one full-width 34 pt pill in the conversation's colour
  ("message" symbol, "Reply in Messages", ↗). It closes the panel and opens the conversation in Messages (a group
  opens Messages).
- **Right-click a message**: Copy.
- **Live**: new messages in the conversation slide in as they arrive (Islet watches Messages' database while the page
  is open and reads it in the background, so the panel never waits for it). A notification for the open conversation
  doesn't show again; others go to the system banner while it's open.
- **Closing**: a click outside, Esc, a swipe up (see Gestures, "Over a list").
- **Permissions**: Full Disk Access (reading Messages' history; onboarding already asks for it) and Contacts (names
  and photos), each asked the first time it's needed.

### Messages inbox (1.5, owner request 2026-11-23)

- A messages pill (blue message bubble and the count) sits beside the battery pill in the panel's header while there
  are unread messages, counting what Messages' badge counts: chats (not messages) with unread incoming messages from
  known senders (someone in the chat is in Contacts, or you've written in it), however old (owner's choice,
  2026-11-23). It reads Messages' history, so reading on the iPhone clears it too. A reply counts as reading what came
  before it.
- Click it for the inbox, in the panel at the conversation's height: "‹ MESSAGES", "n new" in blue and Open Messages,
  then chats with unread messages first (bold name, the preview in white, the time and a count in blue, a faint card
  behind) and the other chats from the last 30 days (12 at most) under them. Each row starts with the same picture as
  the conversation's header (Contacts photo or initial), 34 pt.
- A row opens its conversation. Reading a conversation in the island
  doesn't clear it: the island can only read Messages' history, so it stays unread until it's read in Messages or on
  another device.
- In a conversation, photos show as rounded thumbnails up to 200 pt (click opens them), stickers on their own up to
  96 pt with no bubble, and stickers placed on a message overlap its bottom corner at 40 pt, tilted a little. Other
  files are a chip saying what they are (Video, Audio message, the file's name).
- Emoji & Symbols (⌃⌘Space in search) opens in the desktop's space, under the island's lock-screen space, so
  while it's on screen the panel moves into the desktop's space just under it, and back once it closes.
- With the panel open, a two-finger swipe up closes it only from the notch itself (where nothing is ever drawn);
  anywhere else in the panel the fingers scroll what's under them. Without a notch, from the panel's top strip.

## Without a notch (1.2)

Mockups: the "Islet without a notch" canvas (<https://claude.ai/artifact/PznELF9GV5LZd61mXHWhDo>), with a playable
prototype. Setup's **Your Mac** step (also in Settings → General) asks whether the Mac has a notch, starting on what
macOS reports; "No notch" on a notched Mac uses the no-notch style too. Without a notch (or with the lid closed) the
style is one of:

- **Bubble from the top edge** (default). The island is a black card centred on the screen with the menu bar,
  floating 10 pt below the menu bar, as wide as its body (wings 220 x 34, the panel 500 wide with a 14 pt top
  margin instead of the notch's height).
  - Arriving: a drop falls out of the top edge (0.2 s), snaps free and springs out sideways (0.33 s, soft overshoot,
    from 0.1 s); content fades in as it settles. Leaving: content fades, the card pulls in to a 48 x 30 drop (0.18 s),
    then rises into the edge (0.25 s, no bounce). These are 0.6x the first mockup's timings.
  - The neck: a 4 pt strip along the top edge and the card are blurred together (6 pt) and cut at half opacity, so a
    liquid neck joins them only while the card is near the edge. The card itself is drawn crisp on top.
  - Hover strip: 260 pt wide, the menu bar's height, centred under the camera. Hovering it, a 30 pt drop reaches down
    from the edge to the float height in one smooth motion (0.27 s, no bounce) with a chevron at its tip, and stays
    joined to the edge. A two-finger swipe down (or a click) lets it go: it springs down a touch as a 32 pt drop
    (0.18 s) and bubbles out into the panel.
  - While Mission Control (or another of the Dock's full-screen views) is open, the strip doesn't answer the pointer:
    no drop or chevron, and clicks reach Mission Control's Spaces bar and windows (owner, 2026-11-21). The same goes
    for the notch's hover peek.
  - Only what comes and goes shows: volume and brightness, charging, connection notices, join progress, the face scan
    and the unlock. Music in the wings and the padlock while locked (only the ⌘⇧ reminder shows, every 12 s) are
    left out. Wings never fall back to the chin: there are no menus to cover.
- **Menu bar**: the island hangs from the bottom of the menu bar under Islet's icon (moved in to stay 8 pt clear of
  the screen edge). The stand-in notch is 100 x 32 pt and invisible: idle is zero height, and every shape is a card
  as wide as its body, flat on top. Click the icon to open or close the panel; right-click or Control-click for the
  menu. No hover peek.
- **Off**: no island. Face unlock and the modules keep running.

With no island, or one that only opens from the icon, the menu bar icon always shows (as does the battery icon, 1.5).

## Glass (1.3)

Owner request (2026-11-20): a Liquid Glass look like Siri's island on the iPhone. Revised after the first try: the
island stays mostly black, and only a strip along its bottom edge is glass. To tune by eye on the real display:

- The island is solid black all the way down to the glass strip, notch and wings included.
- The strip is 30% of the island's height below the notch (10 to 44 pt). Over it the black eases off to 12%, so the
  desktop shows through, blurred (Liquid Glass on macOS 26+, the dark HUD material before).
- On the strip: a 1.2 pt white rim at 28% and a soft coloured glow just inside the edge (cyan, indigo, pink, orange,
  blurred 6 pt, 30%).
- The panel's tiles, pills and buttons are glass (Liquid Glass lightly tinted white; before macOS 26, white at 8% with
  a hairline edge) instead of solid #1C1C1E.
- Detail pages (Wi-Fi, Bluetooth, Mirroring, the Sound output list) have no box: the tile's card fades away as it
  glides open and the page sits straight on the island. Rows are Control Center style (icon in a 24 pt circle, 34 pt
  rows, a soft highlight under the pointer); the selected one (current network, output, connected device) sits on a
  glass pill with its icon in a blue circle. Small caps section labels instead of dividers; the Settings… links are
  small glass buttons.
- Settings > General > "Glass look" (on by default) switches back to solid black. Bezel mode's floating card stays
  black for now.

## Search

Owner approved, 2026-11-21 (a search that comes out of the notch, in place of Spotlight). Mockup (playable):
<https://claude.ai/artifact/N5iagkggjhWG5Yu5bGGEvW> (source docs/mockups/search.html). Feasibility: RESEARCH.md
"Search from the notch". Preview: `-IsletDebugShape search -IsletDebugSearch <text>`.

- **Opening**: the search shortcut from anywhere (Settings > Search, and setup; owner, 2026-11-21): two choices, "Use
  ⌘Space for Islet" (Spotlight, and Siri in it, move to another shortcut) or "Keep ⌘Space for Spotlight" (Islet takes
  ⌥Space, ⌃Space or ⇧⌘Space, picked from a menu, the first one Spotlight isn't on). Under them, what's true now, read
  from System Settings every second while it shows: "⌘Space opens Islet. Spotlight and Siri are on ⌥Space." with a
  tick, or "Move Spotlight off ⌘Space" with Open Keyboard Shortcuts… and "Waiting for Spotlight to let go of ⌘Space"
  with a spinner, which ticks itself off once Spotlight has moved. Search works in full-screen apps too. Until
  Spotlight lets go, the Islet page also lists "Spotlight still uses ⌘Space". Pressing the shortcut again closes it.
- **Shape**: a stem and body like the expanded panel, 500 wide, top 16, bottom 30, 10 pt inner curves. It opens with
  "Flow down, then bubble out" and takes the keyboard at once. With wings showing, it opens from the wings' width.
- **Typing while it opens** (owner, 2026-11-21): you can press ⌘Space and type straight away. The opening animation
  never stops or restarts for it: it plays through to the end. The field fades in first (from 0.12 s, with the body
  still at notch width), so letters show as they are typed; the results come in with the rest of the content and
  start reacting as soon as there is a match, even mid-animation. A change in height while it opens is folded into the
  same spring (the target moves, the motion carries on) rather than starting a new animation.
- **From the panel** (owner, 2026-11-21): typing a letter while the panel is open turns it into search with that
  letter in the field: the content cross-fades and the body springs to the search's size.
- **Field** (52 tall): a magnifier (17 pt, `tertiary`) 20 pt in, then the text (19 regular, `text`; placeholder
  "Search" in `tertiary`). A hairline (white 8%, 20 pt in from each side) under it once there are results.
- **Empty field**: a row of the 7 most recently opened apps (40 pt icons, names 10 pt `secondary` under them, one line),
  the selected one on a glass pill. ← → move through them; ↓ from the field goes to them.
- **Results** (as you type, no delay): sections in this order, each under a small caps label (10.5 semibold,
  `tertiary`, 22 tall), at most 3 rows each:
  - **Top hit**: the best match of any kind, 52 tall: icon 32, the name (15 semibold), its kind (11, `tertiary`).
  - **Applications**, **Contacts** (owner, 2026-11-21: your contacts by name, nickname or company; their photo, or their
    initials on a purple circle; the company under a top hit; Return opens the person in Contacts, where Message, Call,
    FaceTime and Email use the right number; needs the Contacts permission Messages already asks for). Quick buttons on
    the right (owner, 2026-11-21): Message, Call, FaceTime, Email as round glass buttons (30 pt on the top hit, always;
    24 pt on other contact rows when selected or under the pointer), only those their saved numbers and emails allow.
    Message opens your one-to-one conversation with them in the notch when there is one, else Messages; Call goes
    through the iPhone (macOS asks first); FaceTime opens FaceTime; Email a new message. Their iPhone or mobile number
    first. **Typing the action** (owner, 2026-11-21): "call mom", "text mom", "facetime mom", "email mom" (also phone,
    ring, message, msg, sms, ft, mail) make the matching contacts that action: "Call Mom" as the top hit with the number
    under it, up to 3 more under Contacts, and Return does it ("↩ Call"). **Shortcuts** (your Shortcuts, run in the background; one Shortcuts icon for all, since theirs
    can't be read), **Files** (from the Spotlight index; the folder on the right, 11 `tertiary`, cut in the middle),
    **Settings** (System Settings pages).
  - Files start from two letters. `~/Library`, hidden folders, the insides of bundles and code projects' build and
    dependency folders (`node_modules`, `build`, `DerivedData`…) are left out; files deep in a folder tree rank lower.
  - Rows are 34 tall: icon 22, name 13 with the matched letters in `text` and the rest `secondary`.
  - **Calculator**: when the text is a sum ("12*7.5", "(3+4)/2"), the top hit is the answer ("= 90", 22 semibold,
    monospaced digits) with the sum above it in `tertiary`. Return copies it.
  - **Ask Siri** (owner, 2026-11-21): Siri lives in Spotlight on macOS 27, and Spotlight answers a typed question with
    Siri on Return; apps have no other way to reach it. Ask Siri opens Spotlight on its own shortcut, types the question
    and presses Return, so Siri is already answering. It comes first, as a "Siri" section with an "Ask Siri" top hit
    (Siri's coloured orb, "“question” · answers in Spotlight", footer "↩ Ask Siri"), when the text starts with "siri"
    (any case; the word is dropped, and nothing else shows), reads like a question (ends in "?", or starts with what,
    how, when, why, who, where, which, can, could, should, would, is, are, do, does, did, will, tell or explain and has
    more words), or nothing here matches; the other results follow by kind. Otherwise it's the first row of More. Needs
    macOS 27, Accessibility and a Spotlight shortcut that isn't search's; Settings > Search can turn it off. The empty
    field's footer says "Type to search, or start with “siri” to ask Siri".
  - **More**: always last: "Search “text” in Spotlight" (presses Spotlight's own shortcut and types the text; without
    Accessibility, or with Spotlight's shortcut still on search's, a Finder search window instead) and "Search the web
    for “text”" (opens the default browser on Settings > General "Search the web with": Google, DuckDuckGo, Bing,
    Ecosia or Kagi; Islet itself sends nothing).
  - Nothing found: "No results for “text”" (13, `secondary`) above More.
- **Matching**: a word's start beats the middle of a word, which beats letters in order ("xcd" finds Xcode; only
  from three letters, and only starting at a word's start, so "mom" doesn't find "System Information"). Ties go to what was opened most recently. Islet remembers what you open from search (on this Mac only) and ranks it higher.
- **Selection**: the first row is selected. The selected row sits on a glass pill (white 10%, hairline edge, radius
  10, inset 8 pt from the body's sides), or `card` with the glass look off. The pointer highlights what it is over
  without moving the selection until it clicks.
- **Height**: the body grows and shrinks with the results (0.22 s, ease-out, no bounce while typing), up to 8 rows;
  beyond that the list scrolls under two fingers (see Gestures, "Over a list").
- **Footer** (28 tall, on the glass strip): what the keys do for the selected row, 10.5 `tertiary`: "↩ Open" (or "↩ Run",
  "↩ Copy"), "⌘↩ Show in Finder" for files and apps, and "esc Clear" on the right ("Type to search apps, files, Shortcuts
  and settings" on an empty field). With the glass look this is the strip, with the black easing to 30% instead of 12%
  so the hints stay readable; without it the body is black to the bottom.
- **Keys**: ↑ ↓ move (wrapping past the ends, skipping labels), ⌘↑ ⌘↓ jump between sections, Return opens, ⌘Return shows in
  Finder, ⌘C copies the selected file or answer, Tab completes the field to the selected name, Esc clears the text,
  a second Esc (or Esc on an empty field) closes.
- **Opening a result**: the row lights up (0.1 s), the content fades (0.12 s) and the island closes as usual. The
  app comes forward as the island closes.
- **Closing**: Esc, the shortcut again, a click outside, a swipe up, opening a result. It doesn't close when the pointer
  leaves, since it's driven from the keyboard.
- **Priority**: search is a panel page: while it is open, notifications go to the system banner and volume and
  brightness use the system display, as with the other pages. A face scan still takes over.
- **Without a notch**: bubble mode drops it from the top edge as a card; menu bar mode drops it under the icon. Same
  contents.
- **Not in search (for now)**: clipboard history (it would mean Islet watching everything you copy), web results and
  answers (no network), mail and messages.

Decided (owner, 2026-11-21): ⌘Space is the default (Spotlight's own shortcut is moved). **Changed (owner, 2026-11-23): ⌥Space
is the default, so Islet doesn't fight Spotlight; ⌘Space is a choice in Settings > Search.**; the "Search the web" row
stays; typing in the open panel starts a search.

## Settings (1.4)

Owner approved, 2026-11-21. Mockup: <https://claude.ai/artifact/BGmqPdjdPVkqjTfugVrKbu> (source
docs/mockups/settings.html).

- **Window**: System Settings' layout, the native sidebar and grouped form; 720 × 520 to start, resizable, remembers its
  size and the last page. The window's title is the page's name.
- **Sidebar**: Islet's status row on top (app icon, "Islet 1.4", a green dot and "Everything is set up", or an orange dot
  and "N things need attention"), then General, Notch, Notifications, Search, Battery, Face Unlock, and below a gap
  Permissions and Updates. A page something breaks has a count badge.
- **Islet (status page)**: one big status line (green tick, or orange with the count), then "To fix" with each issue
  and its fix (Allow…, Keyboard Shortcuts…, Install and Restart; else Show, which goes to its page), then "Features"
  (owner, 2026-11-21, replacing the "At a glance" tiles): each feature with what it does, one state ("Ready", "Ready
  on ⌘Space", "Off", "Needs Full Disk Access", with a green or orange dot) and its switch; Face Unlock has Set Up… until
  it is set up. Messages sits indented under Notifications behind a turn-down-right arrow (in setup too) and hides while they're off.
- **What counts as an issue**: a permission that's off and needed by a feature that's on (see "Features (1.4)"); the
  volume keys not reaching Islet although
  Accessibility is on (Restart Islet); Now playing unavailable; Spotlight still holding the search shortcut; the face
  model missing; Face Unlock paused by a rejected password; an update ready to install. Everything that works stays
  quiet.
- **Permissions** (owner, 2026-11-21): a green line "Your features have what they need" while nothing is off, else the
  issues on top. Then "Used by your features" (each with the features that use it, and Allowed or Allow…) and "Not
  needed" (dimmed: "Optional. Names instead of numbers…" with Allow…, or "Nothing you have on uses it"). Now playing sits
  under "Not a permission". Islet checks everything again whenever the window comes to the front, so allowing one in
  System Settings and coming back clears it.
- **Face Unlock**: one status line (on, off, not set up, needs attention) with the explanation, then the face (Scan
  Again…, "Enrolled · 7 of 24 looks learned") and password (Change…), Test recognition, Security and learning (the Security choice with the chosen level's description, the learning
  switch, learned looks), and
  Remove at the bottom.
- **Search**: a switch for search itself, then "Shortcut" (the choice under "Search", "Opening"), then "Results": the
  Ask Siri switch (with "Needs Accessibility…" in orange when it's off) and the web search engine.
- **Setup** (owner, 2026-11-21): Welcome, your Mac, "What should Islet do?" (a checkbox per feature, each with what it
  needs; the island itself ticked and greyed), "Allow what you picked" (each needed permission once, "For Messages and
  Focus. Opens System Settings…", ticking itself off; then "Optional" ones; "Skip for now" until all are allowed), "How
  should search open?" (only when Search is ticked), Face Unlock (only when ticked), and "You're set" with each feature's
  state, open at login and the menu bar icon. General has Run Setup… and Quit.

## Quick info (1.4)

Owner approved, 2026-11-21. Mockup: <https://claude.ai/artifact/FHqTKpznAKMcB8YQVdLybj> (source
docs/mockups/quick-info.html).

- **When**: the moment the pointer is over the notch while nothing is showing (no music, notification, level or
  event; not hidden music's peek), with no delay (owner, 2026-11-21: it's a quick peek). It replaces the hover peek. Leaving folds it back. Settings > Notch "Quick
  info on hover" (on by default). Notch mode only (not menu bar or bezel mode).
- **Wide bar** (menu bar has room): the volume wide bar's shape (wings 60 pt a side and a 26 pt body, bottom 18). Left
  wing: the time (13 semibold, no AM/PM) over the date (9.5, `secondary`, "Sat, Nov 21"). Right wing: the percentage
  (11.5 semibold) over the battery (the battery page's glyph, 28 × 13; green while plugged in, red at 20% or less, a bolt
  plugged in). Each centred in its wing, so they mirror. Body: Wi-Fi (icon and network, 12 semibold; the hotspot icon
  for a hotspot; "Not connected" or "Wi-Fi Off" with the crossed-out icon) and the connected Bluetooth device ("2
  devices" for more; left out when none), centred together 24 pt apart.
- **Chin** (no room): the notch as the stem, a 340 × 60 body (top 16, bottom 18, 10 pt curves). First row, 18 pt in:
  the time and date on the left, the battery and percentage on the right. Second row: Wi-Fi and Bluetooth centred.
- **Motion**: the shape springs out like the wings, the text fading in at 0.06 s (0.12 s in the chin). The swell applies.
- **Opening the panel** (a click): the Wi-Fi icon and name glide into the Wi-Fi tile's round button and status line,
  the Bluetooth ones into its tile, and the percentage and battery into the header's battery chip, on the shape's
  spring (0.5, damping 0.82). The time and date fade (0.1 s). Everything else in the panel fades in a beat later
  (0.3 s from 0.16 s). The island clips everything, and the tiles don't clip while pieces glide into them, so nothing
  shows outside the shape or gets cut off on the way.

## Shazam (1.6)

Owner request, 2026-11-23: name the song playing nearby from the notch.

- **Starting it**: a round Shazam button (the blue Shazam mark on a glass circle, 22 pt) in the controls' header,
  at its right end (beside the mini player or the gear; see "Flush panel"); it closes the panel and the notch listens. Or pull it in with two fingers (below).
  Settings > Dynamic Peninsula > Features "Shazam" (on by default) removes both.
- **Pulling it in** (owner, 2026-11-23: "drag Shazam in with some resistance"): two fingers sideways over the idle
  notch (quick info, the peek; not over media, where they skip). The mark follows the fingers in from the edge they
  move away from (fingers right: from the left), against a rubber band like the skip (progress = 1 − 1 / (1 + travel
  / 85 pt); the commit point is half way, 85 pt of travel). It grows from half size, sharpens and fills in blue as it
  comes; a ring round it fills toward the commit point. The island makes room: the closed notch grows its wings (or a
  chin), quick info stretches a little and fades and blurs out under it. At the commit point the ring closes, the mark
  turns full blue and pops (spring 0.22, 0.55) and the trackpad clicks firmly; going back over it, a light tick. A
  light tick also as the pull first catches. Past the point it keeps creeping in a little. Lifting past the point (and
  not flung back out) listens, the mark staying where it is, in the wing it came from, with the equaliser in the other.
  It lands with a small bounce (owner, 2026-11-23: "not too dramatic"): from the 108% it popped to at the commit
  point it dips to 90%, rebounds to 103.5% and settles at 100%, on springs, in about 0.4 s, with a light tap on the
  trackpad at the same moment (felt only while a finger is still on it). Not with Reduce Motion.
  Lifting short of it: the mark springs back out the way it came at the fingers' speed (response 0.34, damping 0.66),
  and nothing runs.
- **Listening** (up to 15 s): the wide bar with a body, like volume (or the chin when the menu bar has no room). The
  Shazam mark (white S on blue, 22 pt) in the left wing beats softly while three blue rings ripple out of it; a
  five-bar equaliser (cyan to blue) dances in the right wing; "Listening…" in the body with a light sweeping across
  it. A click stops it, or dragging it away (below).
- **Stopping it** (owner, 2026-11-23): two fingers up or down over Shazam while it listens follow the fingers
  instead of the usual one-shot swipe, against a band (progress = 1 − 1 / (1 + travel / 60 pt); commit point half
  way). Up pushes it back into the notch: the island narrows (up to 46 pt) and its body draws up. Down stretches it
  off the bottom like taffy: the body grows longer and narrower. Either way the content follows a little (up 6 pt,
  down 10 pt), shrinks to 86% and fades to about half, the ripples fade, the equaliser flattens and the mark loses its
  colour. At the commit point the text becomes "Let go to stop" and the trackpad clicks firmly (a light tick going
  back over it, and as the drag first catches). Lifting past it stops listening and the island folds away; short of
  it, it springs back (response 0.36, damping 0.62) and keeps listening. If Shazam answers mid-drag, the drag lets go.
- **A song**: the island grows into a 360 × 76 card under the notch. The mark flies down into the artwork's place and
  grows into a 52 pt rounded square, the cover lands on it with a spring and a blue ring bursts out of it, then the
  title (14 semibold) and artist (12, `secondary`) slide in from the left. On the right, two round glass buttons
  (26 pt): copy ("Title – Artist" to the clipboard) and open in Apple Music. Hovering the title or the artist shows a
  small copy icon beside it, and a click copies just that line. A copy turns its icon into a green check for 1.4 s,
  with a light tap on the trackpad. A firm tap on
  the trackpad when it's found. It stays 8 s (held while hovered, 3 s after the pointer leaves). A click opens it in
  Apple Music (Shazam's page when Apple Music doesn't have it); a swipe up puts it away.
  The song is also added to the Shazam library, as Control Center's Music Recognition does, so it's in Shazam's history
  on the iPhone.
- **No match**: the mark turns grey and shakes its head, the bars lie down, "No match. Try closer to the sound" (3 s).
  A click listens again. Errors the same way in red ("Couldn't reach Shazam", 4 s); with the microphone off, "Allow
  the microphone in Settings ›", which a click opens.
- Priority: under notifications (a banner shows over it and hands back), above charging, events and media. Reduce Motion: no ripples, beat, bars or burst.
- **Network and microphone**: the microphone is asked the first time it listens and only used while it does. ShazamKit
  sends a signature of the sound (not the audio) to Shazam, and the cover is downloaded from Apple; nothing else.
  It hears the room, so music playing through headphones isn't heard (see RESEARCH.md "Shazam").

## Mac Stats (1.7)

Owner request and approval, 2026-11-24: CPU, GPU and memory use, power draw, temperature and fan speed in the menu bar,
a panel with a page for each part, and manual fan control. Our own design in the app's style, not a copy of other stats
apps (the owner's reference screenshots were too cluttered). Mockups: <https://claude.ai/artifact/E8TmfaU8DeGm4nyXuQ3ixB>
(menu bar meters, the temperature, power and fan readouts, the panel, the CPU, Memory, GPU and Fans pages, and
Settings; the pages and Settings work in Play).

A feature of its own, "Mac Stats" (Features list and Settings > Mac Stats). Off, nothing is measured.

### Colours

Each part has its own colour, the same in the menu bar, the panel and the pages. None is warm, so yellow and red only
ever mean a warning.

| Part | Dark menu bar / panel | Light menu bar |
|---|---|---|
| Efficiency cores | green `#32D74B` | `#248A3D` |
| Performance cores | blue `#0A84FF` (text `#409CFF`) | `#0040DD` |
| GPU | purple `#BF5AF2` | `#8944AB` |
| Memory | cyan `#64D2FF` | `#0071A4` |
| Warning / critical | yellow `#FFD60A` / red `#FF453A` | macOS's darker yellow / `#D70015` |

- CPU core groups and the GPU turn yellow above 70% and red above 90%, once they've stayed there about 5 s (so a
  spike doesn't flash). Memory turns yellow at memory pressure "warning" and red at "critical"; how full it is never
  colours it (macOS fills spare memory with cache).
- Settings "Colour each part" off: the bars use the menu bar's colour, like the battery. "Warn in yellow and red" off:
  no warning colours.

### Menu bar

One status item, left of Islet's own icon (battery or pill), holding left to right: the readouts, then the meters.
Both are one item so the spacing is ours, not macOS's gap between items (owner, 2026-11-24: meters on the right,
spacing kept tight). Either half can be off; with both off, nothing shows (Settings says so).

- **Meters** (owner, 2026-11-24, after trying it: wider, and the CPU as one bar; then taller and a little wider to read
  at a glance): three bars 18 pt tall (of the item's 22) with fully
  rounded ends, 2.5 pt apart, filling from the bottom. The CPU bar is 14 pt wide and split down the middle with no gap:
  its left half fills for the efficiency cores (green), its right half for the performance cores (blue), each with its
  own warning colour. Then the GPU and memory, 7 pt each. With one core type turned off, the other is a plain 7 pt bar.
  The empty part is the menu bar's colour at 30%. CPU halves are the mean use of that core type; GPU is device
  utilisation; memory is used ÷ installed.
- **Readouts** (owner, 2026-11-24): no icons, two lines in 10 pt (numbers semibold with monospaced digits), right-aligned,
  in two columns 5 pt apart and 6 pt before the meters:
  - Temperature over power: "106°" (no unit letter; °F or °C by region; the CPU's average by default, Settings can pick
    the hottest CPU core or the GPU; yellow from 80 °C, red from 95 °C) over "9 W" (the whole Mac's draw, SMC `PSTR`,
    never coloured). With one of them off, the other sits alone in the middle.
  - The faster fan: "5.3k" over "rpm" (under 1,000 rpm in whole tens: "840"), or "Off" over "fans". The unit line is
    dimmer and in the normal (not monospaced) font. While fan control holds the fans it reads "manual" instead of "rpm".
  - The fan is a number, not a percentage: next to the bars a lone "41%" would read as a load. The turning fan icon of
    the first build went with the icons.
  - The whole item is about 91 pt wide with everything on.
- Each readout and each bar can be turned off on its own (Settings).
- Click: the stats panel. Right-click or Control/Option-click: Islet's menu, as for the battery.

### Panel

Drops from the item like the battery stats and looks the same (300 pt; Liquid Glass with the glass look, else the dark
HUD panel; title row, label/value rows at 13 pt, rules between sections, small glass pills). Numbers refresh every 2 s
while open (Settings: "Update every").

- Title row: "Mac", and the uptime on the right ("Up 6 days, 10 hr").
- Four glass tiles, 2 × 2, each opening its page:
  - CPU: total %, and an E and a P row, each a small bar in its colour with its %.
  - GPU: %, GPU memory in use, a purple 10-minute sparkline.
  - Memory: %, "28.2 of 48 GB", a bar of apps / kept for macOS / compressed in cyan shades, "Pressure normal".
  - Power: watts, "CPU 2.1 · GPU 0.8 W", a neutral sparkline. It opens nothing yet (still to decide: see ROADMAP), so
    it has no chevron; the others have a small one by their name.
  - A tile's big number turns yellow or red with its warning level (the CPU tile with its busier core type).
- Temperature: CPU, GPU, SSD (no memory sensor is known yet). CPU and GPU turn yellow or red like the menu bar.
- Fans: the mode as a pill ("Automatic ›", opens the Fans page), then each fan, "Off" or its rpm.
- Footer: "Updated every 2 s" and an "Activity Monitor…" pill.

Pages fade in place of the overview (see Motion), with a round back button and the part's name;
the panel keeps its width.

- **CPU**: total % on the right; 10 minutes of load stacked by core type (efficiency green under performance blue,
  100% and 50% marked); "Cores", one 12 pt bar per core grouped Efficiency then Performance, each group's %; User ·
  System, Speed, Temperature (average · hottest); "Using the most", five apps with their icons and % (100% is one
  core, with a note saying so); Activity Monitor….
- **Memory**: "28.2 of 48 GB"; the pressure in words on the right (Normal, High, Critical); 10 minutes of how full it
  was, a thin bar per reading in cyan, yellow or red by the pressure at the time, and a line saying full is fine and the
  colour is pressure; the breakdown bar and rows (Apps, Kept for macOS, Compressed,
  Free, Swap used); the five apps using the most; Activity Monitor….
- **GPU**: % on the right; 10 minutes of use in purple; Neural Engine, Memory in use, Power, Temperature (no frame
  rate: nothing readable gives it, RESEARCH.md);
  the apps using the GPU right now (no rows of 0%); Activity Monitor….
- **Fans**: the CPU temperature on the right; each fan's speed with a bar up to its maximum; "Control": Automatic /
  Manual / Full Speed, styled like the Energy Mode switch.
  - Automatic: macOS runs them (on Apple silicon they stay off until the Mac is warm).
  - Manual: one slider for both fans, from the fans' minimum to maximum (2,300 to 7,800 rpm here), "Quietest" to
    "Fastest". If the Mac gets hotter than that speed can handle, macOS takes over again.
  - Full Speed: both fans at their maximum.
  - A note: back to Automatic when Dynamic Peninsula quits, the Mac sleeps or restarts; changing the fans needs a
    small helper installed once with the password. Manual and Full Speed only show with "Let me control the fans" on.
  - With "Let me control the fans" off, the page shows "Control: Automatic" (or "Manual" while something else holds
    them) and the Automatic line.
  - With it on and the helper not installed: "Install Fan Helper…" (macOS then asks for it to be allowed in Login Items,
    which takes the password); waiting for that: "Open Login Items…". While taking the fans over (about 6 s the first
    time): a small spinner and "Taking over the fans…". A failure, or the helper giving the fans back on its own (the
    Mac got hot, the app stopped answering), shows in red under the switch.
  - Manual starts at the fans' speed now, or 3,000 rpm when they're off; the slider moves in 100 rpm steps and is sent
    when let go.

### App names in the lists (owner, 2026-11-24)

The "Using the most" lists name things the way a person would, while still being exact about what uses the resource:

- Helper processes count under their app: "Claude Helper" and "Claude Helper (Renderer)" are one row, "Claude", with
  the app's icon and the sum. The same for browsers' content processes and other helpers.
- macOS's own processes get a plain name and say they're part of macOS, with the process name small and secondary
  underneath so it can still be looked up: "Spotlight indexing" (corespotlightd), "Drawing the screen"
  (WindowServer), "Sound" (coreaudiod), "Screenshot" (screencapture). One that isn't in the list keeps its own name.
- Hovering a grouped row shows what's in it.

### Quitting from the lists (owner, 2026-11-24)

- On the CPU and Memory pages, hovering a row shows a small ⓧ before its value. A click quits it the way the Dock's Quit
  does, so an app can still ask about unsaved work; anything that isn't an app gets SIGTERM. The value reads
  "Quitting…" meanwhile.
- If it's still running 4 seconds later, the row offers a red Force Quit, which says it loses anything unsaved.
- No ⓧ for macOS's own processes, anything of root or another user, apps in /System, or Dynamic Peninsula itself. The
  GPU page has none.

### Motion (owner, 2026-11-24)

Like the battery stats' power flow, everything in the panel moves rather than jumps:

- Each reading glides in on the same spring: numbers roll to their new value, bars and the memory breakdown ease to it,
  and the charts slide along as time passes.
- The charts and tile sparklines show the 10 minutes in 5-second slots (120), each the average of its readings, the
  newest at the right edge; the sparklines slide left a step as each new slot starts. Until there are 10 minutes of
  readings the left stays empty.
- The "Using the most" lists always take the room of five rows of one height, so a row with a second line, or a list
  that grows or shrinks, never changes the page's height.
- Going between the overview and a page is a plain fade: the old page fades out (0.12 s), the new one fades in (0.2 s).
  Nothing slides or grows in (owner, 2026-11-24: simpler is better here).
- The panel eases to the new page's size (0.25 s), its top edge staying put, the content kept to the top. The battery
  stats panel does the same when its content changes size.

### Settings > Mac Stats

A page between Battery and Face Unlock, in the usual grouped form:

- At the top, the feature's icon (the four meters), "Mac Stats", what it does, and its switch. Off greys out the rest.
- **Menu bar**: "Usage meters" with a switch for each bar under it (Efficiency cores, Performance cores, GPU, Memory,
  each with its colour dot); "Temperature, power and fans" with a switch for each under it (Temperature with its
  choice: CPU average, Hottest CPU core, GPU). Child rows sit indented behind a turn-down-right arrow, greyed while
  their parent is off. With nothing on, an orange line: "Nothing is on in the menu bar, so there's nowhere to open the
  stats from."
- **Look**: "Colour each part", "Warn in yellow and red", "Update every" (1, 2 or 5 seconds).
- **Fan Control**: "Let me control the fans" (off by default; turning it off gives the fans back); while on, "Fan
  helper" with its state and Install…, Open Login Items… or Remove….
- The Features list (status page and setup) has one row, "Mac Stats", with its switch; the parts are on this page.
- Each meter's row has its colour as a small square (faded while "Colour each part" is off).

## Features (1.4)

Owner approved, 2026-11-21. Mockup: <https://claude.ai/artifact/Dr9mECwP7ZuYuaacvnYXrr> (source
docs/mockups/features.html).

You pick what Islet does, and it only asks for what that needs. The island itself (now playing, charging and battery,
the controls) is always on and needs nothing.

| Feature | Needs | Off means |
|---|---|---|
| Volume and brightness | Accessibility | the keys go to macOS's own display |
| Notifications | Accessibility | banners stay in the corner |
| Messages (inside Notifications) | Full Disk Access, Contacts, Control Messages | message banners open in Messages |
| Focus | Full Disk Access | no Focus notice or icon |
| Search | nothing | no shortcut, and typing in the panel doesn't search |
| Shazam (1.6) | nothing (the microphone is asked the first time it listens) | no button in the controls, no swipe |
| Face Unlock | Camera, Accessibility (and the login password) | the lock screen as usual |
| Mac Stats (1.7) | nothing (fan control: a helper installed once with the password) | no stats in the menu bar, nothing measured |

- A permission only counts as missing while a feature that needs it is on. Some add to features that work without
  them and are never shown as problems: Location (Wi-Fi names on the island), Contacts (names on notifications, people
  in search), Accessibility (the wider layout when the menu bar has room; Ask Siri).
- Turning Search off remembers its shortcut for when it comes back on.

## Visual tokens

| Token          | Value     | Use                                  |
|----------------|-----------|--------------------------------------|
| island         | `#000000` | the island                           |
| card           | `#1C1C1E` | cards inside the panel               |
| text           | `#F5F5F7` | primary text, level bars             |
| secondary      | `#A1A1A6` | secondary text                       |
| tertiary       | `#8E8E93` | times, small labels                  |
| green          | `#32D74B` | music bars, charging, success, unlock |
| cyan           | `#64D2FF` | face scan sweep                      |
| red            | `#FF453A` | low battery, no match                |
| red text       | `#FF6961` | red text on black                    |
| artwork placeholder | `#5E5CE6` | when there's no artwork         |

Type: the system font (SF Pro). Compact text 13 semibold; numbers use monospaced digits.
Icons: SF Symbols equivalents of the mockup icons (`speaker.wave.2`, `sun.max`, `bolt.fill`,
`lock`/`lock.open`, `checkmark`, `battery.*`).
