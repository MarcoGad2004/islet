import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let face: FaceUnlockCoordinator
    private let levels: LevelsController
    private let media: MediaMonitor

    init(face: FaceUnlockCoordinator, levels: LevelsController, media: MediaMonitor) {
        self.face = face; self.levels = levels; self.media = media
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Islet Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(face: face, levels: levels, media: media))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
