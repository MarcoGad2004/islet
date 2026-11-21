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

    /// Opens Settings, on `page` when given (else the page it was left on).
    func show(page: SettingsPage? = nil) {
        if let page { UserDefaults.standard.set(page.rawValue, forKey: SettingsPage.storageKey) }
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(face: face, levels: levels, media: media, focus: focus, wifi: wifi,
                                                                  runSetup: { [weak self] in self?.runSetup?() },
                                                                  setTitle: { [weak self] t in DispatchQueue.main.async { self?.window?.title = t } }))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.setContentSize(NSSize(width: 720, height: 520))
            w.isReleasedWhenClosed = false
            if !w.setFrameUsingName("IsletSettings") { w.center() }
            w.setFrameAutosaveName("IsletSettings")
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
