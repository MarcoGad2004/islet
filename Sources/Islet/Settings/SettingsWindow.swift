import AppKit
import SwiftUI

/// Placeholder until M9 (launch at login, permissions, face unlock setup).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Islet Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView:
                Text("Settings arrive in M9.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
