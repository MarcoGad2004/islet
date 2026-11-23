# Architecture

What it should look like and do is in [DESIGN.md](DESIGN.md). This file is how to build it.

## Layers

1. **App shell**: agent app (`LSUIElement`), a menu bar item (Settings, Pause Islet, Quit), launch
   at login via `SMAppService`.
2. **Notch window**: one borderless, non-activating `NSPanel` at the top centre of the built-in
   display, sized to the largest shape (expanded panel) and transparent outside the island. It sits
   above the menu bar, joins all Spaces and shows over full-screen apps
   (`canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, `ignoresCycle`). Clicks outside the
   island shape must pass through to the menu bar and apps below: toggle `ignoresMouseEvents`
   based on whether the pointer is inside the current shape. Hosts SwiftUI via `NSHostingView`.
3. **Notch geometry**: from `NSScreen`: notch height = `safeAreaInsets.top`; notch x-range =
   between `auxiliaryTopLeftArea.maxX` and `auxiliaryTopRightArea.minX`. Recompute on
   `NSApplication.didChangeScreenParametersNotification`. No built-in notched display (lid closed):
   hide the island.
4. **Layout check**: decides wings vs chin (see DESIGN.md "Menu bar width check"). Inputs: AX menu
   bar frames of the frontmost app, and status-item window bounds from `CGWindowListCopyWindowInfo`.
5. **Island state machine**: one `@Observable` store holding the current presentation
   (closed / peek / wings(content) / chin(content) / scan / expanded(page)), the priority queue of
   short events, the "media hidden" flag, and timers for auto-dismiss.
6. **Island shape and views**: one custom `Shape` with animatable stem/body dimensions and inner
   curves; content views per feature, each with a wings and a chin variant.
7. **Modules** (each isolated; publishes events/state to the store):
   - `Media`: now playing info and commands.
   - `Power`: battery level, charging state, time to full/empty (IOKit power source notifications).
   - `Levels`: volume/mute/brightness keys, setting volume and brightness, output devices.
   - `Lock`: screen lock/unlock notifications (`com.apple.screenIsLocked` / `screenIsUnlocked` via
     `DistributedNotificationCenter`).
   - `FaceUnlock`: camera capture (built-in camera only), face match, liveness (challenges, `FacePulse` light
     check, `SpoofCheck` MiniFASNet model in `Models/AntiSpoof.mlpackage`), Keychain password, typing it into the lock
     screen.
   - `Notifications`: `NotificationWatcher` observes Notification Center's banner windows (`AXObserver`), moves each one
     off screen, reads it and hands it to the store; the card's Show / Close press the banner's own actions.
   - `Search`: `SearchIndex` (apps from the app folders, Shortcuts through `/usr/bin/shortcuts`, System Settings
     pages, files from the Spotlight index through `NSMetadataQuery`), `SearchModel` (sections, ranking, keys) and
     `SearchShortcut` (the Carbon hot key, Spotlight's own shortcut from `com.apple.symbolichotkeys`, the hand-off).
     The panel's key monitor (`NotchController`) sends keys to `IslandStore.handleKey`.
8. **Gestures**: two-finger swipes are `scrollWheel` events delivered to the panel while the pointer
   is over it; use precise deltas and the gesture phase, with a threshold (≈40 pt) per gesture.
9. **Settings**: a small SwiftUI window: launch at login, permissions status, face unlock setup.

## Folder layout

```
Sources/Islet/
  App/          entry point, app delegate, menu bar item
  Notch/        panel, geometry, layout check, island shape, state store
  Modules/      Media/, Power/, Levels/, Lock/, FaceUnlock/
  Views/        compact (wings/chin) and expanded views, face scan view
  Settings/
  Support/      design tokens, helpers
Tests/IsletTests/
```

## Permissions

| Permission            | Needed by                                   | Without it                    |
|-----------------------|---------------------------------------------|-------------------------------|
| Accessibility         | menu width check, media/volume key tap, typing the password | chin only; no key HUD; no face unlock |
| Camera                | face unlock                                 | no face unlock                |
| Input Monitoring      | possibly for the key event tap (verify)     | no volume/brightness HUD      |

Add `NSCameraUsageDescription` to the Info.plist (in `project.yml`).

## Principles

- Modules are independent; one failing must not take down the rest.
- No network access except updates: the latest GitHub release, read from GitHub's public API with no account, when "Check for updates" is clicked and automatically (a minute after launch, then every 6 hours, re-checked after wake; can be turned off in Settings). Installing only ever starts from a click, and only if the update is signed by the same developer.
- CPU near zero when the island is closed: no timers or polling while idle; the layout check runs
  on events, not a loop.
- Face data and the stored password never leave the Mac.
