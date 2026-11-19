import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    var runSetup: (() -> Void)?
    private let face: FaceUnlockCoordinator
    private let levels: LevelsController
    private let media: MediaMonitor
    private let focus: FocusMonitor
    private let wifi: WiFiController

    init(face: FaceUnlockCoordinator, levels: LevelsController, media: MediaMonitor, focus: FocusMonitor, wifi: WiFiController) {
        self.face = face; self.levels = levels; self.media = media; self.focus = focus; self.wifi = wifi
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Islet Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(face: face, levels: levels, media: media, focus: focus, wifi: wifi, runSetup: { [weak self] in self?.runSetup?() }))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
