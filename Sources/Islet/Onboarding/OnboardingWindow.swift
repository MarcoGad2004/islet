import AppKit
import SwiftUI

/// The first-run setup window. Shown once after install (and again from Settings > "Run setup again").
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let doneKey = "onboardingDone"
    static var needed: Bool { !UserDefaults.standard.bool(forKey: doneKey) }

    private var window: NSWindow?
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
            // Resizable, and never taller than the screen: the footer's buttons have to stay in reach.
            let available = (NSScreen.main?.visibleFrame.height ?? 900) - 60
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: min(700, max(480, available))),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.contentMinSize = NSSize(width: 520, height: 480)
            w.title = "Welcome to Dynamic Peninsula"
            w.isReleasedWhenClosed = false
            w.delegate = self
            let host = NSHostingView(rootView: OnboardingView(face: face, levels: levels, media: media, focus: focus, wifi: wifi) { [weak self] in
                self?.window?.close()
            })
            host.sizingOptions = [.minSize] // the window's size, not the view's ideal one
            w.contentView = host
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        if face.isEnrolling { face.cancelEnrolment() }
        window?.contentView = nil
        window = nil
    }
}
