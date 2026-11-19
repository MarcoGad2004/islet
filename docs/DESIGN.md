# Islet v1 design (locked)

This is the source of truth for what v1 looks like and how it behaves. It was settled in a
design session on 2026-11-18 using an interactive mockup canvas:
<https://claude.ai/artifact/9gDTDbkfLsf2UXTDE6WJ8U> (private; open the "v1 locked" page, and play
the "v1 prototype" artboard to see the motion). The canvas is a web approximation: where it and
this file disagree, this file wins.

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

- Body: 300 × 36, directly under the stem. Corners: top 10, bottom 16.
- 10 pt concave curves join the stem to the body's top edge on both sides.
- Volume and brightness **always** use the chin (so the 16-step bar fits), even when wings fit.

### Stem and body (large)

Used for the face scan and the expanded panel, regardless of the width check:

| Shape         | Size under the stem | Corners                              |
|---------------|---------------------|--------------------------------------|
| Face scan     | notch width × 150   | bottom 44, flush with the stem sides |
| Expanded      | 500 × 216           | top 16, bottom 30, 10 pt inner curves |

### All shapes

| Shape         | Size                              | Corners            |
|---------------|-----------------------------------|--------------------|
| Closed        | the notch (≈190 × 34, measured)   | bottom 10          |
| Hover peek    | notch + 16 wide, + 6 tall         | bottom 14          |
| Wings         | notch + 120 wide, notch height    | bottom 12          |
| Chin          | stem + 300 × 36 body              | top 10, bottom 16  |
| Face scan     | stem + notch-wide × 150 body      | bottom 44          |
| Expanded      | stem + 500 × 216 body             | top 16, bottom 30  |

Hover peek only happens when nothing is showing.

## Motion

### Flow down, then bubble out

Any change that puts a body below the stem:

1. The body flows straight down from behind the stem **at notch width** (0.34 s, ease-out).
2. From 0.2 s it bubbles out sideways to its full width with a soft overshoot (≈0.6 s spring).
3. Corners settle from 0.12 s; the inner curves fade in from 0.22 s.
4. Content fades in (opacity, plus scale from 96%) at ≈0.36 s, after the shape has mostly settled.

Going back up runs in reverse: content fades (0.12 s), width pulls in (0.26 s, ease-in), then the
body slides up behind the stem (0.32 s, starting at 0.18 s).

Wings: width springs out with the same overshoot (0.55 s); content fades in after 0.12 s.

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
stays visible. On a match the dots fly into a check (0.5 s), then the check **flies to the left wing**
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

- **Ring**: 48 ticks in 8 sectors (3 o'clock = sector 0, counter-clockwise), `#2C2C2E` when empty.
  A sector's ticks spring to cyan, staggered 35 ms, once two good face samples are captured there.
- **Face dots**: the same 33-dot grid as the scan at 1.7×, shifted a few points with the head
  (parallax), with the cyan sweep while a face is visible.
- **Head dot**: an 8 pt cyan dot inside the ring follows the head like a level bubble. Touching the
  ring captures that direction. "Straight ahead" is calibrated from the first ~0.6 s (3 samples).
- **Labels**: "Looking for you" → "Hold still" → "Slowly move your head in a circle" → "Keep going".
- **Done**: dots fly into a green check (8 ms stagger), ring turns green, "Face enrolled", fold back
  after 2.4 s. **Failure** (no consistent scan, or 2 min): ring dims, red label, fold back.
- Click and hover are ignored while it runs; Cancel is in Settings.

### Face scan

The scan shape flows down at notch width (no bubble-out; it stays notch-wide).

- **Looking**: a face-shaped grid of dots (7 × 7 grid at 8 pt spacing, keeping the dots within a
  26 pt radius of the centre: about 33 dots, shown at ≈1.35×) inside a thin ring (`#2C2C2E`). A
  cyan (`#64D2FF`) sweep runs down the grid row by row on a 1.3 s loop. Label: "Looking for you".
- **Match**: the dots fly into a check-mark shape in a quick stagger (≈8 ms per dot, 0.5 s each),
  turning green; the ring turns green; label "Welcome back". After ≈0.9 s the shape pulls up and
  the **lock opens** animation plays.
- **No match**: dots and ring turn red (`#FF453A`), the grid shakes sideways (0.45 s), label "Not
  recognized". After 3 failed tries, stop until the next lock and leave the password field.

## Features

### Media

- Shows while anything is playing; hides 30 s after pause.
- **Wings**: artwork (22 pt, radius 6) on the left; level bars on the right.
- **Chin**: artwork, "Title · Artist" centred (scrolls if long), level bars.
- **Expanded (media playing)**: media only. Header "NOW PLAYING" and a collapse chevron. Artwork
  80 pt (radius 14), title (17 semibold), artist, album, previous / play-pause / next on the right,
  then a draggable scrubber with elapsed and total time. Clicking the artwork brings the playing
  app forward.

### Charging and battery

Short events; each shows, then hands back to what was showing.

| Event                | Duration | Wings                          | Chin                                     |
|----------------------|----------|--------------------------------|------------------------------------------|
| Charger connected    | 3 s      | green bolt, green %            | bolt, "Charging · 1:10 to full", %       |
| Fully charged        | 3 s      | green full battery, "100%"     | same with label                          |
| Low battery 20%, 10% | 4 s      | red battery, red % (`#FF6961`) | red battery, "Low battery", red %        |
| Charger removed      | none     | -                              | -                                        |

"Fully charged" also fires at the charge limit if one is set. Low battery only fires when not charging.

### Volume and brightness

- Shows on volume, mute and brightness keys. Hides 1.5 s after the last press.
- Always the chin: icon (speaker or sun), a 16-step bar (steps 9 × 6 pt, 3 pt gaps, on
  `#F5F5F7`, off `#3A3A3C`), the value 0–100 on the right. Both use the same white.
- Muted: speaker with a cross, bar dims (on `#636366`, off `#2C2C2E`) but keeps the level, value "Off".
- Clicking it opens the expanded panel's Display and Sound page, even while media plays.

### Expanded panel

One page, no tabs. Opened by clicking the island.

- **Media playing**: media only (see Media).
- **Nothing playing**: "DISPLAY AND SOUND". A narrow battery block on the left (112 pt wide:
  bolt or battery icon, big percentage, state, time to full or left), and on the right two wide
  cards: Display (sun, slider, %) and Volume (speaker, slider, output device name that opens an
  output picker).
- Closes 1 s after the pointer leaves, on a click outside, on Esc, or on a two-finger swipe up.

### Face unlock

Convenience, explicitly weaker than Touch ID. Agreed by the owner.

- Only unlocks **this Mac's lock screen**. Never used for sudo, Keychain prompts, App Store, System
  Settings or anything else.
- After a restart the password is still needed (FileVault unlocks the disk before any app runs).
- Flow: screen locked → camera checks for a face → on a match, the app types the user's login
  password (stored in the Keychain) into the lock screen → unlock animation.
- 3 attempts per lock, then stop.
- Setup in Settings: confirm with Touch ID or the password, look at the camera to enrol, then enter
  the login password to store in the Keychain. Face data and the password never leave the Mac.
- Feasibility is **unproven**: see `docs/RESEARCH.md`. Build the spike before any UI.

### Unlock animation

Plays when macOS reports the screen unlocked (whatever unlocked it). See "Lock opens".

## Behaviour

### Priority

Face scan > lock opens > volume/brightness > charging/battery > media. Short events cover media and
hand back when they end.

### Gestures

With the pointer over the island:

- **Two-finger swipe up**: hides what is showing. Media stays hidden until swiped back or a
  different app starts playing. Short events (volume, charging, unlock) still appear. On the open
  panel, swipe up closes it.
- **Two-finger swipe down**: brings hidden media back; with nothing hidden, opens the panel.
- When media is hidden, hovering the notch shows a 4 pt green dot just below the camera.
- Click: opens the panel (Display and Sound if a level bar was showing).

### Menu bar width check

- Front app's menus: read with the Accessibility API (menu bar of the frontmost app, each item's
  frame). Free space on the left = notch left edge − right edge of the last menu item.
- Status icons: read window bounds of other apps' status-item windows in the menu bar. Free space
  on the right = left edge of the nearest icon − notch right edge.
- Wings only when both sides ≥ 68 pt. Re-check on app switch, menu changes and display changes.
- No Accessibility permission, or the check fails: always use the chin.

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
