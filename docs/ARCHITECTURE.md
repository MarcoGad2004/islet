# Architecture (planned)

## Layers
1. **App shell**: agent app (`LSUIElement`), menu bar item for settings/quit, launch at login.
2. **Notch window**: borderless, non-activating `NSPanel` pinned to the top-center of the built-in display, floating above normal windows. Hosts a SwiftUI view via `NSHostingView`.
3. **Notch geometry**: detect the notch size per screen (safe area insets and the auxiliary top areas on `NSScreen`), recompute on display changes.
4. **State machine**: `closed` -> `hover-peek` -> `open`, driving size/shape animation.
5. **Modules (live activities)**: each is a small, isolated unit that publishes state and provides a compact and an expanded view.
6. **Settings**: `UserDefaults`/`@AppStorage`, a simple settings window.

## Planned folder layout
```
Sources/Islet/
  App/          entry point, app delegate, menu bar item
  Notch/        panel, geometry, state machine, shape/animation
  Modules/      NowPlaying/, Battery/, Calendar/, Shelf/ ...
  Settings/
  Support/      helpers, extensions
Tests/IsletTests/
```

## Principles
- Each module independent, so one can break without taking down the rest
- No network access unless a module needs it
- Keep CPU near zero when the notch is closed
