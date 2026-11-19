import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notch = NotchController()
    private lazy var faceUnlock = FaceUnlockCoordinator(island: notch.store)
    private lazy var settings = SettingsWindowController(face: faceUnlock)
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var paused = false
    #if DEBUG
    private lazy var spike = LockSpike(notch: notch)
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch.start()
        buildMenuBarItem()
        #if DEBUG
        // `Islet -IsletDebugShape chin` starts with a shape showing (wings, chin, scan, expanded).
        switch UserDefaults.standard.string(forKey: "IsletDebugShape") {
        case "wings": notch.store.setBase(.wings)
        case "chin": notch.store.setBase(.chin)
        case "scan": notch.store.setBase(.scan)
        case "expanded": notch.store.expand()
        case "enrol": previewEnrolment()
        default: break
        }
        #endif
    }

    private func buildMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Islet")
        let menu = NSMenu()

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        let pause = menu.addItem(withTitle: "Pause Islet", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pauseItem = pause

        #if DEBUG
        menu.addItem(.separator())
        let debug = NSMenuItem(title: "Show shape", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, tag) in [("Automatic (hover)", 0), ("Wings", 1), ("Chin", 2), ("Face scan", 3), ("Expanded", 4), ("Enrolment preview", 5)] {
            let i = sub.addItem(withTitle: title, action: #selector(debugShape(_:)), keyEquivalent: "")
            i.target = self
            i.tag = tag
        }
        debug.submenu = sub
        menu.addItem(debug)
        let spikeItem = menu.addItem(withTitle: "Face unlock spike (M2)", action: #selector(toggleSpike(_:)), keyEquivalent: "")
        spikeItem.target = self
        #endif

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { settings.show() }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem?.title = paused ? "Resume Islet" : "Pause Islet"
        notch.setPaused(paused)
    }

    #if DEBUG
    /// Plays a fake enrolment (no camera) so the animation can be judged: a dot circles, sectors fill, check.
    private func previewEnrolment() {
        let model = EnrolmentModel()
        notch.store.enrolment = model
        notch.store.setBase(.enrol)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            model.snapshot.faceVisible = true
            try? await Task.sleep(for: .seconds(0.8))
            model.snapshot.calibrated = true
            for step in 0..<(8 * 20) {
                let a = Double(step) / 20 * (.pi / 4)
                model.snapshot.x = cos(a) * 1.05
                model.snapshot.y = sin(a) * 1.05
                if step % 20 == 10 { model.snapshot.filled[(step / 20) % 8] = true }
                try? await Task.sleep(for: .milliseconds(45))
            }
            model.snapshot.x = 0; model.snapshot.y = 0
            model.phase = .success
            try? await Task.sleep(for: .seconds(2.6))
            notch.store.setBase(nil)
        }
    }

    @objc private func toggleSpike(_ sender: NSMenuItem) {
        spike.setEnabled(!spike.enabled)
        sender.state = spike.enabled ? .on : .off
    }

    @objc private func debugShape(_ sender: NSMenuItem) {
        let store = notch.store
        store.collapse()
        switch sender.tag {
        case 1: store.setBase(.wings)
        case 2: store.setBase(.chin)
        case 3: store.setBase(.scan)
        case 4: store.setBase(nil); store.expand()
        case 5: previewEnrolment()
        default: store.setBase(nil)
        }
    }
    #endif
}
