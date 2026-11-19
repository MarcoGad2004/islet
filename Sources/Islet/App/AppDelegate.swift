import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notch = NotchController()
    private lazy var faceUnlock = FaceUnlockCoordinator(island: notch.store)
    private let power = PowerMonitor()
    private let levels = LevelsController()
    private let media = MediaMonitor()
    private let focus = FocusMonitor()
    private let wifi = WiFiController()
    private let bluetooth = BluetoothController()
    private let display = DisplayToggles()
    private let airdrop = AirDropController()
    private lazy var settings = SettingsWindowController(face: faceUnlock, levels: levels, media: media, focus: focus, wifi: wifi)
    private lazy var onboarding = OnboardingWindowController(face: faceUnlock, levels: levels, media: media, focus: focus, wifi: wifi)
    private var statusItem: NSStatusItem?
    private var menuBarObserver: NSKeyValueObservation?
    private var menuBarShown = true
    private var pauseItem: NSMenuItem?
    private var paused = false
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch.start()
        faceUnlock.unlock.start()
        startModules()
        buildMenuBarItem()
        notch.store.openSettings = { [weak self] in self?.settings.show() }
        settings.runSetup = { [weak self] in self?.onboarding.show() }
        if OnboardingWindowController.needed { onboarding.show() }
        applyMenuBarVisibility()
        // Watch only this key. (Setting `isVisible` itself writes to UserDefaults, so observing every change recursed.)
        menuBarObserver = UserDefaults.standard.observe(\.showMenuBarIcon, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyMenuBarVisibility() }
        }
        #if DEBUG
        // `Islet -IsletDebugShape chin` starts with a shape showing (wings, chin, scan, expanded).
        switch UserDefaults.standard.string(forKey: "IsletDebugShape") {
        case "wings": notch.store.setBase(.wings)
        case "chin": notch.store.setBase(.chin)
        case "scan": notch.store.setBase(.scan)
        case "expanded": notch.store.expand()
        case "morph":
            // Wings, then a switch to chin one second later, to judge the morph.
            let store = notch.store
            store.layoutCheck = { true }
            store.recomputeLayout()
            store.showCharge(ChargeEvent(kind: .connected, percent: 69, minutesToFull: 72))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.3))
                store.layoutCheck = { false }
                store.recomputeLayout()
            }
        case "locksequence": previewLockSequence()
        case "enrol": previewEnrolment()
        case "charge": notch.store.showCharge(ChargeEvent(kind: .connected, percent: 69, minutesToFull: 72))
        case "full": notch.store.showCharge(ChargeEvent(kind: .full, percent: 100))
        case "low": notch.store.showCharge(ChargeEvent(kind: .low, percent: 20))
        case "volume": notch.store.showLevel(LevelState(kind: .volume, value: 0.5))
        case "spike": runSpike()
        case "spikeactive": let s = ControlSpike(); controlSpike = s; Task { await s.runActive() }
        case "spikebt": let s = ControlSpike(); controlSpike = s; Task { await s.runBluetoothConnect() }
        case "spikewatch": let s = ControlSpike(); controlSpike = s; Task { await s.watch() }
        case "spikewrites": let s = ControlSpike(); controlSpike = s; Task { await s.runWrites() }
        case "focuson", "wificonnect", "btconnect", "eventchin":
            let wide = UserDefaults.standard.string(forKey: "IsletDebugShape") != "eventchin"
            notch.store.layoutCheck = { wide }
            notch.store.eventLayoutCheck = { wide }
            notch.store.recomputeLayout()
            let e: IslandEvent
            switch UserDefaults.standard.string(forKey: "IsletDebugShape") {
            case "focuson": e = IslandEvent(kind: .focusOn, icon: "moon.fill", title: "Do Not Disturb", detail: "On")
            case "wificonnect": e = IslandEvent(kind: .wifi, icon: "wifi", title: "NLDeco_MLO", detail: "Connected")
            case "btconnect": e = IslandEvent(kind: .bluetooth, icon: "airpodspro", title: "Marco’s AirPods Pro", detail: "Connected")
            default: e = IslandEvent(kind: .wifi, icon: "wifi", title: "NLDeco_MLO", detail: "Connected")
            }
            notch.store.showEvent(e)
        case "levelwide":
            notch.store.layoutCheck = { true }
            notch.store.recomputeLayout()
            notch.store.showLevel(LevelState(kind: .brightness, value: 21.0 / 32))
        case "muted": notch.store.showLevel(LevelState(kind: .volume, value: 0.5, muted: true))
        case "brightness": notch.store.showLevel(LevelState(kind: .brightness, value: 0.75))
        case "unlock": notch.store.playUnlock()
        case "scanlive": faceUnlock.unlock.simulate()
        default: break
        }
        #endif
    }

    /// Wires each module to the island store. A failing module must not take down the others.
    func applicationWillTerminate(_ notification: Notification) { media.stop() }

    private func startModules() {
        // Quit cleanly on SIGTERM/SIGINT too, so the media helper process never outlives the app.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApplication.shared.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }

        let store = notch.store
        store.power = power
        store.levels = levels
        store.mediaMonitor = media
        store.layoutCheck = { [weak store] in
            guard let g = store?.geometry else { return false }
            return LayoutChecker.wingsFit(g)
        }

        store.eventLayoutCheck = { [weak store] in
            guard let g = store?.geometry else { return false }
            return LayoutChecker.eventWingsFit(g)
        }
        store.focus = focus; store.wifi = wifi; store.bluetooth = bluetooth; store.display = display; store.airdrop = airdrop

        focus.onChange = { [weak store] old, new in
            if let new { store?.showEvent(IslandEvent(kind: .focusOn, icon: new.symbol, title: new.name, detail: "On")) }
            else if let old { store?.showEvent(IslandEvent(kind: .focusOff, icon: old.symbol, title: old.name, detail: "Off")) }
        }
        focus.start()
        wifi.onConnected = { [weak store] ssid in store?.showEvent(IslandEvent(kind: .wifi, icon: "wifi", title: ssid, detail: "Connected")) }
        wifi.start()
        bluetooth.onConnected = { [weak store] name, icon in store?.showEvent(IslandEvent(kind: .bluetooth, icon: icon, title: name, detail: "Connected")) }
        bluetooth.start()
        display.refresh()
        airdrop.refresh()

        power.onEvent = { [weak store] in store?.showCharge($0) }
        power.start()

        levels.onChange = { [weak store] in store?.showLevel($0) }
        levels.start()

        media.onChange = { [weak store] in store?.setMedia($0) }
        media.start()

        // Re-run the width check on app switch, and retry permission-gated things when we come to the front.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.recomputeLayout() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.recomputeLayout() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.levels.retryTap() }
        }
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
        for (title, tag) in [("Automatic (hover)", 0), ("Wings", 1), ("Chin", 2), ("Face scan", 3), ("Expanded", 4), ("Enrolment preview", 5), ("Simulate lock scan (no typing)", 6), ("Preview lock-screen sequence", 11), ("Preview unlock animation", 7), ("Preview charging", 8), ("Preview low battery", 9), ("Preview volume", 10)] {
            let i = sub.addItem(withTitle: title, action: #selector(debugShape(_:)), keyEquivalent: "")
            i.target = self
            i.tag = tag
        }
        let spike = sub.addItem(withTitle: "Run Control Center spike (M10)", action: #selector(runSpike), keyEquivalent: "")
        spike.target = self
        debug.submenu = sub
        menu.addItem(debug)

        #endif

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func applyMenuBarVisibility() {
        let show = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        guard show != menuBarShown else { return }
        menuBarShown = show
        statusItem?.isVisible = show
    }

    #if DEBUG
    private var controlSpike: ControlSpike?
    @objc private func runSpike() {
        let s = ControlSpike(); controlSpike = s
        Task { await s.run() }
    }
    #endif

    @objc private func openSettings() { settings.show() }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem?.title = paused ? "Resume Islet" : "Pause Islet"
        notch.setPaused(paused)
    }

    #if DEBUG
    /// Plays the lock-screen story with a fake match: closed lock in the wings, the scan drops down, the dots
    /// become a check that flies left while the lock opens, then everything folds back.
    private func previewLockSequence() {
        let store = notch.store
        Task { @MainActor in
            store.setLockScreen(true)
            try? await Task.sleep(for: .seconds(1.5))
            let model = ScanModel()
            store.scan = model
            store.setBase(.scan)
            try? await Task.sleep(for: .seconds(1.6))
            model.faceVisible = true
            try? await Task.sleep(for: .seconds(1.0))
            model.phase = .match
            model.matchedAt = Date()
            try? await Task.sleep(for: .milliseconds(650))
            model.flown = true
            store.presentationChanged()
            try? await Task.sleep(for: .seconds(2.5))
            store.setBase(nil)
            store.setLockScreen(false)
        }
    }

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

    @objc private func debugShape(_ sender: NSMenuItem) {
        let store = notch.store
        store.collapse()
        switch sender.tag {
        case 1: store.setBase(.wings)
        case 2: store.setBase(.chin)
        case 3: store.setBase(.scan)
        case 4: store.setBase(nil); store.expand()
        case 5: previewEnrolment()
        case 6: faceUnlock.unlock.simulate()
        case 11: previewLockSequence()
        case 7: store.playUnlock()
        case 8: store.showCharge(ChargeEvent(kind: .connected, percent: 69, minutesToFull: 72))
        case 9: store.showCharge(ChargeEvent(kind: .low, percent: 20))
        case 10: store.showLevel(LevelState(kind: .volume, value: 0.5))
        default: store.setBase(nil)
        }
    }
    #endif
}


extension UserDefaults {
    /// KVO key for the "Show menu bar icon" setting.
    @objc dynamic var showMenuBarIcon: Bool { bool(forKey: "showMenuBarIcon") }
}
