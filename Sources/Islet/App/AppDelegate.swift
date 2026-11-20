import AppKit
import SwiftUI

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
    private let sidecar = SidecarController()
    private let notifications = NotificationWatcher()
    private let faceTime = FaceTimeMonitor()
    private lazy var settings = SettingsWindowController(face: faceUnlock, levels: levels, media: media, focus: focus, wifi: wifi)
    private lazy var onboarding = OnboardingWindowController(face: faceUnlock, levels: levels, media: media, focus: focus, wifi: wifi)
    private var statusItem: NSStatusItem?
    private var menuBarObserver: NSKeyValueObservation?
    private var notchlessObserver: NSKeyValueObservation?
    private var hasNotchObserver: NSKeyValueObservation?
    private var statusMenu: NSMenu?
    private var menuBarShown = true
    private var pauseItem: NSMenuItem?
    private var paused = false
    private var signalSources: [DispatchSourceSignal] = []
    /// FaceTime in the notch (DESIGN.md "Calls"): off until its design is redone in a later update.
    static let callsEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch.menuBarAnchor = { [weak self] in self?.statusItemAnchor() }
        notch.start()
        if UserDefaults.standard.bool(forKey: "IsletHandoff") { notch.setIslandVisible(false) } // shown once fully drawn
        faceUnlock.unlock.start()
        startModules()
        buildMenuBarItem()
        // Without a notch the island hangs from the icon, which only has a place once the menu bar lays it out.
        Task { @MainActor [weak self] in self?.notch.screenChanged(); self?.applyMenuBarVisibility() }
        notch.store.openSettings = { [weak self] in self?.settings.show() }
        // A Settings… button in the panel opened System Settings: close the panel so the window isn't under it.
        NotificationCenter.default.addObserver(forName: SystemSettings.didOpen, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notch.store.collapse() }
        }
        settings.runSetup = { [weak self] in self?.onboarding.show() }
        if OnboardingWindowController.needed { onboarding.show() }
        applyMenuBarVisibility()
        // Watch only this key. (Setting `isVisible` itself writes to UserDefaults, so observing every change recursed.)
        menuBarObserver = UserDefaults.standard.observe(\.showMenuBarIcon, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyMenuBarVisibility() }
        }
        notchlessObserver = UserDefaults.standard.observe(\.notchlessStyle, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.notch.screenChanged(); self?.applyMenuBarVisibility() }
        }
        hasNotchObserver = UserDefaults.standard.observe(\.hasNotch, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.notch.screenChanged(); self?.applyMenuBarVisibility() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyMenuBarVisibility() }
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
        case "lockhint": notch.store.setLockScreen(true); notch.store.setLockHint(true)
        case "enrol": previewEnrolment()
        case "charge": notch.store.showCharge(ChargeEvent(kind: .connected, percent: 69, minutesToFull: 72))
        case "full": notch.store.showCharge(ChargeEvent(kind: .full, percent: 100))
        case "low": notch.store.showCharge(ChargeEvent(kind: .low, percent: 20))
        case "volume": notch.store.showLevel(LevelState(kind: .volume, value: 0.5))
        case "spike": runSpike()
        case "spikeactive": let s = ControlSpike(); controlSpike = s; Task { await s.runActive() }
        case "spikebt": let s = ControlSpike(); controlSpike = s; Task { await s.runBluetoothConnect() }
        case "mediapage":
            let store = notch.store
            store.expand()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                store.showMediaPage()
            }
        case "modecycle":
            let store = notch.store
            store.expand()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                store.setControlDetail(.sound)
                try? await Task.sleep(for: .seconds(3))
                store.setControlDetail(nil)
                try? await Task.sleep(for: .seconds(3))
                store.showMediaPage()
                try? await Task.sleep(for: .seconds(3))
                store.showControlsPage()
            }
        case "detailcycle":
            let store = notch.store
            store.expand()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                store.setControlDetail(.bluetooth)
                try? await Task.sleep(for: .seconds(2.5))
                store.setControlDetail(nil)
                try? await Task.sleep(for: .seconds(2))
                store.setControlDetail(.wifi)
            }
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
        case "notification", "notifications":
            let store = notch.store
            store.showNotification(NotificationItem(id: UUID(), app: "Messages", title: "Mom", subtitle: nil,
                                                    body: "Are you coming for dinner tonight? Dad is making the lentil soup, and we can watch the match after.",
                                                    icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Messages.app"), appURL: nil))
            if UserDefaults.standard.string(forKey: "IsletDebugShape") == "notifications" {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    store.showNotification(NotificationItem(id: UUID(), app: "Mail", title: "Your order has shipped", subtitle: nil,
                                                            body: "It arrives Friday between 9 AM and 1 PM",
                                                            icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Mail.app"), appURL: nil))
                }
            }
        case "ring": notch.store.setCall(CallState(phase: .ringing))
        case "call": notch.store.setCall(CallState(phase: .active, name: "Mom", connectedAt: Date().addingTimeInterval(-81)))
        case "updated":
            // What the new copy shows after updating itself (notes from CHANGELOG.md's newest section).
            let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let log = (try? String(contentsOf: repo.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)) ?? ""
            let section = log.components(separatedBy: "\n## ").dropFirst().first.map { $0.components(separatedBy: "\n").dropFirst().joined(separator: "\n") } ?? ""
            Updater.pending = Updater.Pending(from: "1.2.1", to: Updater.currentVersion, notes: section)
            Updater.announceIfJustUpdated()
            if UserDefaults.standard.bool(forKey: "IsletDebugNotes") { ReleaseNotesWindow.show(version: Updater.currentVersion, notes: section) }
        case "selfupdate":
            // The real update, start to finish (pair with IsletDebugUpdateDMG for a local test release).
            let u = Updater.shared
            Task { @MainActor in
                u.check()
                while u.state == .checking || u.state == .idle { try? await Task.sleep(for: .milliseconds(200)) }
                if case .available(let tag) = u.state { u.install(tag) }
            }
        case "updating", "updatingwide":
            // The steps of an install and the handoff's ending, without downloading or quitting. "updatingwide" pretends
            // the menu bar has room for the wide bar.
            if UserDefaults.standard.string(forKey: "IsletDebugShape") == "updatingwide" {
                notch.store.layoutCheck = { true }
                notch.store.recomputeLayout()
            }
            Task { @MainActor in
                let show = { (s: ConnectionProgress.State, f: Double) in
                    Updater.showInIsland?(ConnectionProgress(name: "Islet", hotspot: false, state: s, icon: "arrow.down.circle.fill",
                                                             tint: Color(hex: 0x0A84FF), fraction: f), nil)
                }
                try? await Task.sleep(for: .seconds(1.5))
                for pct in stride(from: 0, through: 100, by: 5) {
                    show(.working("Downloading 1.2.2 · \(pct)%"), Updater.downloadShare * Double(pct) / 100)
                    try? await Task.sleep(for: .milliseconds(150))
                }
                show(.working("Verifying the update…"), 0.78); try? await Task.sleep(for: .seconds(1.2))
                show(.working("Installing 1.2.2…"), 0.88); try? await Task.sleep(for: .seconds(1))
                show(.working("Restarting Islet…"), Updater.restartFraction); try? await Task.sleep(for: .seconds(1.5))
                Updater.showInIsland?(ConnectionProgress(name: "Islet", hotspot: false, state: .done, icon: "sparkles", tint: .isletGreen,
                                                         doneText: "Updated to 1.2.2", actionLabel: "What's new", hold: 8, fraction: 1), nil)
            }
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
        // An update's handoff: start in the old copy's layout so the two islands match, then measure as usual.
        let handoffWide = UserDefaults.standard.string(forKey: "IsletHandoffWide").map { $0 == "YES" }
        let handoffUntil = Date().addingTimeInterval(5)
        store.layoutCheck = { [weak store] in
            if let handoffWide, Date() < handoffUntil { return handoffWide }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "IsletDebugWide") { return true }
            #endif
            guard let g = store?.geometry else { return false }
            return g.virtual || LayoutChecker.wingsFit(g) // under the menu bar nothing can be covered
        }

        store.eventLayoutCheck = { [weak store] in
            guard let g = store?.geometry else { return false }
            return g.virtual || LayoutChecker.eventWingsFit(g)
        }
        store.focus = focus; store.wifi = wifi; store.bluetooth = bluetooth; store.display = display; store.airdrop = airdrop; store.sidecar = sidecar

        focus.onChange = { [weak store] old, new in
            if let new { store?.showEvent(IslandEvent(kind: .focusOn, icon: new.symbol, title: new.name, detail: "On", tint: new.color)) }
            else if let old { store?.showEvent(IslandEvent(kind: .focusOff, icon: old.symbol, title: old.name, detail: "Off")) }
        }
        focus.start()
        wifi.onConnected = { [weak store] ssid, hotspot in
            store?.showEvent(hotspot ? IslandEvent(kind: .hotspot, icon: "personalhotspot", title: ssid, detail: "Hotspot")
                                     : IslandEvent(kind: .wifi, icon: "wifi", title: ssid, detail: "Connected"))
        }
        wifi.onProgress = { [weak store] in store?.showProgress($0) }
        Updater.showInIsland = { [weak store] p, action in store?.showProgress(p, action: action) }
        Updater.clearIsland = { [weak store] in store?.clearProgress() }
        Updater.revealIsland = { [weak self] in self?.notch.setIslandVisible(true) }
        Updater.islandIsWide = { [weak store] in store?.wingsFit == true }
        Updater.pauseForHandoff = { [weak self] in self?.levels.stopTap(); self?.media.stop() }
        Updater.resumeAfterHandoff = { [weak self] in self?.levels.retryTap(); self?.media.start() }
        Updater.announceIfJustUpdated()
        store.updater = Updater.shared
        Updater.shared.startAutomaticChecks()
        wifi.start()
        bluetooth.onConnected = { [weak store] name, icon in store?.showEvent(IslandEvent(kind: .bluetooth, icon: icon, title: name, detail: "Connected")) }
        bluetooth.start()
        display.refresh()
        airdrop.refresh()
        sidecar.start()

        // Notifications and FaceTime calls (DESIGN.md "Notifications and calls").
        notifications.canTake = { [weak store] in store?.canTakeNotification == true }
        notifications.onNotification = { [weak store] in store?.showNotification($0) }
        // Calls are left for a later update (owner, 2026-11-20): the code is here, but nothing feeds the island yet.
        if Self.callsEnabled { notifications.onRinging = { [weak self] in self?.faceTime.setRinging($0) } }
        store.notificationShow = { [weak self] in self?.notifications.show($0) }
        store.notificationClose = { [weak self] in self?.notifications.close($0) }
        store.notificationExpired = { [weak self] in self?.notifications.expired($0) }
        notifications.start()
        faceTime.onChange = { [weak store] in store?.setCall($0) }
        store.callMute = { [weak self] in self?.faceTime.toggleMute() }
        store.callCamera = { [weak self] in self?.faceTime.toggleCamera() }
        store.callEnd = { [weak self] in self?.faceTime.end() }
        if Self.callsEnabled { faceTime.start() }

        power.onEvent = { [weak store] in store?.showCharge($0) }
        power.start()

        levels.onChange = { [weak store] in store?.showLevel($0) }
        levels.start()

        media.onChange = { [weak store] in store?.setMedia($0) }
        media.start()

        // Re-run the width check on app switch, and retry permission-gated things when we come to the front.
        // Media from the app in front stays out of the notch.
        store.setFrontApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak store] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                store?.setFrontApp(id)
                store?.recomputeLayout()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.recomputeLayout() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.levels.retryTap(); self?.notifications.retry(); self?.faceTime.retry() }
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
        // The menu opens from the click handler: in menu bar mode a plain click opens the island instead.
        statusMenu = menu
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let e = NSApp.currentEvent
        let wantsMenu = e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true || e?.modifierFlags.contains(.option) == true
        if notch.inMenuBar && !wantsMenu {
            notch.toggleFromMenuBar()
            return
        }
        guard let item = statusItem, let menu = statusMenu else { return }
        item.menu = menu
        item.button?.performClick(nil) // shows the menu with the icon highlighted
        item.menu = nil
    }

    /// Where the island hangs without a notch: under the icon, from the menu bar's bottom edge.
    private func statusItemAnchor() -> (x: CGFloat, bottom: CGFloat, screen: CGRect)? {
        guard let item = statusItem, item.isVisible, let w = item.button?.window, let screen = w.screen else { return nil }
        return (x: w.frame.midX, bottom: w.frame.minY, screen: screen.frame)
    }

    /// With no island, or one that only opens from the icon, the icon is the way to Settings, so it stays.
    private func applyMenuBarVisibility() {
        let wanted = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        let show = wanted || notch.store.geometry.map { $0.mode == .menuBar } ?? true
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
    /// KVO key for what Islet does without a notch (`NotchlessStyle`).
    @objc dynamic var notchlessStyle: String? { string(forKey: "notchlessStyle") }
    /// KVO key for the owner's "This Mac has a notch" choice.
    @objc dynamic var hasNotch: Bool { bool(forKey: "hasNotch") }
}
