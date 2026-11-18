# Open technical questions (verify before building)

These are things to confirm against Apple docs / current macOS behavior, not settled facts.

1. **Notch detection**: how to reliably get notch width/height via `NSScreen` (`safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`). Check on this MacBook Pro's built-in display and with a lid closed / external display.
2. **Window level and Spaces**: which `NSWindow.Level` and `collectionBehavior` keep the panel visible over full-screen apps and across Spaces, without stealing focus.
3. **Now Playing access**: the system media APIs are private and access has been restricted for third-party apps in recent macOS versions. Research what currently works (per-app scripting for Music/Spotify vs. system-wide) before committing to a design.
4. **Hover tracking** over the notch area when the app is not active (`NSTrackingArea` vs. global mouse monitors, and any permission prompts).
5. **Permissions**: Accessibility, Calendar, Bluetooth, etc. Which modules need which.
6. **Distribution**: self-signed/Developer ID vs. just running from Xcode builds. Personal use only, so keep it simple.
