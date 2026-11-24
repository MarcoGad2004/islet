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
    private let messages = MessagesStore()
    private lazy var settings = SettingsWindowController(face: faceUnlock, levels: levels, media: media, focus: focus, wifi: wifi)
    private lazy var onboarding = OnboardingWindowController(face: faceUnlock, levels: levels, media: media, focus: focus, wifi: wifi)
    private var statusItem: NSStatusItem?
    private lazy var batteryStats = BatteryStatsPanel(power: power)
    private var iconObservers: [NSKeyValueObservation] = []
    private var menuBarObserver: NSKeyValueObservation?
    private var notchlessObserver: NSKeyValueObservation?
    private var hasNotchObserver: NSKeyValueObservation?
    private var statusMenu: NSMenu?
    /// nil until first applied: macOS remembers a hidden status item across launches, so it's always set once.
    private var menuBarShown: Bool?
    private var pauseItem: NSMenuItem?
    private var paused = false
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch.menuBarAnchor = { [weak self] in self?.statusItemAnchor() }
        notch.start()
        // Search from the notch (DESIGN.md "Search").
        SearchShortcut.shared.onPress = { [weak self] in self?.notch.store.toggleSearch() }
        SearchShortcut.shared.apply()
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
        // The battery stats panel open under the icon, to look at it.
        case "batterystats":
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, let button = self.statusItem?.button else { return }
                self.batteryStats.show(under: button)
            }
        // The unlock with the volume turned up during it, for the level row under it (repeats so it can be watched).
        case "unlocklevel":
            Task { @MainActor [weak self] in
                for _ in 0..<6 {
                    try? await Task.sleep(for: .seconds(1.5))
                    self?.notch.store.playUnlock()
                    for v in stride(from: 0.3, through: 0.8, by: 0.1) {
                        try? await Task.sleep(for: .seconds(0.25))
                        self?.notch.store.showLevel(LevelState(kind: .volume, value: v))
                    }
                }
            }
        case "scan": notch.store.setBase(.scan)
        case "expanded": notch.store.expand()
        case "setup":
            // `-IsletDebugShape setup -IsletDebugStep choose` opens setup on that step.
            onboarding.show()
        case "settings":
            // `-IsletDebugShape settings -IsletDebugPage faceUnlock` opens Settings on that page.
            settings.show(page: UserDefaults.standard.string(forKey: "IsletDebugPage").flatMap(SettingsPage.init(rawValue:)))
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
        case "messagesspike": let s = MessagesSpike(); messagesSpike = s; Task { await s.run() }
        case "messagessend": let s = MessagesSpike(); messagesSpike = s; Task { await s.sendTest() }
        case "searchspike": let s = SearchSpike(); searchSpike = s; Task { await s.run() }
        case "searchkeys": let s = SearchSpike(); searchSpike = s; Task { await s.runKeys() }
        case "search":
            // `-IsletDebugShape search -IsletDebugSearch saf`: opens search a second after launch with that text typed.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.notch.store.openSearch(initial: UserDefaults.standard.string(forKey: "IsletDebugSearch") ?? "")
            }
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
        case "bannerspike": let s = BannerSpike(); bannerSpike = s; Task { await s.run() }
        case "spikewatch": let s = ControlSpike(); controlSpike = s; Task { await s.watch() }
        case "spikewrites": let s = ControlSpike(); controlSpike = s; Task { await s.runWrites() }
        case "focuson", "wificonnect", "eventchin":
            let wide = UserDefaults.standard.string(forKey: "IsletDebugShape") != "eventchin"
            notch.store.layoutCheck = { wide }
            notch.store.eventLayoutCheck = { wide }
            notch.store.recomputeLayout()
            let e: IslandEvent
            switch UserDefaults.standard.string(forKey: "IsletDebugShape") {
            case "focuson": e = IslandEvent(kind: .focusOn, icon: "moon.fill", title: "Do Not Disturb", detail: "On")
            case "wificonnect": e = IslandEvent(kind: .wifi, icon: "wifi", title: "NLDeco_MLO", detail: "Connected")
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
        case "notification", "notifications", "notificationpill":
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
            // `notificationpill`: the two, then the panel opened over them (as a swipe down would), then the list.
            if UserDefaults.standard.string(forKey: "IsletDebugShape") == "notificationpill" {
                Task { @MainActor in
                    store.showNotification(NotificationItem(id: UUID(), app: "Mail", title: "Your order has shipped", subtitle: nil,
                                                            body: "It arrives Friday between 9 AM and 1 PM",
                                                            icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Mail.app"), appURL: nil))
                    try? await Task.sleep(for: .seconds(1))
                    store.swipeDown()
                    try? await Task.sleep(for: .seconds(5))
                    store.openNotificationList()
                    try? await Task.sleep(for: .seconds(5))
                    store.closeNotificationList()
                }
            }
        case "conversation":
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if let id = self.messages.chatID(withText: "Islet test") ?? self.messages.latestChatID() { self.notch.store.openChat(id) }
            }
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
                    Updater.showInIsland?(ConnectionProgress(name: "Dynamic Peninsula", hotspot: false, state: s, icon: "arrow.down.circle.fill",
                                                             tint: Color(hex: 0x0A84FF), fraction: f), nil)
                }
                try? await Task.sleep(for: .seconds(1.5))
                for pct in stride(from: 0, through: 100, by: 5) {
                    show(.working("Downloading 1.2.2 · \(pct)%"), Updater.downloadShare * Double(pct) / 100)
                    try? await Task.sleep(for: .milliseconds(150))
                }
                show(.working("Verifying the update…"), 0.78); try? await Task.sleep(for: .seconds(1.2))
                show(.working("Installing 1.2.2…"), 0.88); try? await Task.sleep(for: .seconds(1))
                show(.working("Restarting Dynamic Peninsula…"), Updater.restartFraction); try? await Task.sleep(for: .seconds(1.5))
                Updater.showInIsland?(ConnectionProgress(name: "Dynamic Peninsula", hotspot: false, state: .done, icon: "sparkles", tint: .isletGreen,
                                                         doneText: "Updated to 1.2.2", actionLabel: "What's new", hold: 8, fraction: 1), nil)
            }
        case "scanlive": faceUnlock.unlock.simulate()
        default: break
        }
        #endif
    }

    /// Wires each module to the island store. A failing module must not take down the others.
    func applicationWillTerminate(_ notification: Notification) { media.stop() }

    /// System Settings' "Quit & Reopen" (after a permission is turned on) doesn't always bring the app back, so the
    /// app sees to it itself.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Relauncher.quitIsFromSystemSettings() { Relauncher.reopenAfterExit() }
        return .terminateNow
    }

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

        store.panelLayoutCheck = { [weak store] in
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "IsletDebugWide") { return true }
            #endif
            guard let g = store?.geometry, !g.virtual else { return false }
            return LayoutChecker.panelFits(g)
        }
        store.eventLayoutCheck = { [weak store] in
            guard let g = store?.geometry else { return false }
            return g.virtual || LayoutChecker.eventWingsFit(g)
        }
        store.focus = focus; store.wifi = wifi; store.bluetooth = bluetooth; store.display = display; store.airdrop = airdrop; store.sidecar = sidecar

        focus.onChange = { [weak store] old, new in
            guard Feature.focus.isOn else { return }
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
        // Devices connecting are left to macOS, which shows its own card for them (owner, 2026-11-24).
        bluetooth.start()
        display.refresh()
        airdrop.refresh()
        sidecar.start()

        // Notifications (DESIGN.md "Notifications").
        notifications.canTake = { [weak store] in store?.canTakeNotification($0) == true }
        store.messages = messages
        if Feature.messages.isOn { messages.startInbox() }
        notifications.onNotification = { [weak store] in store?.showNotification($0) }
        store.notificationShow = { [weak self] in self?.notifications.show($0) }
        store.notificationClose = { [weak self] in self?.notifications.close($0) }
        store.notificationExpired = { [weak self] in self?.notifications.expired($0) }
        store.notificationAction = { [weak self] in self?.notifications.perform($0, action: $1) }
        notifications.start()

        power.onEvent = { [weak store] in store?.showCharge($0) }
        power.onEventUpdate = { [weak store] in store?.updateCharge($0) }
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
            MainActor.assumeIsolated { self?.levels.retryTap(); self?.notifications.retry() }
        }
    }

    /// Where the icon starts, in points from the menu bar's right edge: just left of Control Center and the clock.
    private static let startPosition = 230

    private func buildMenuBarItem() {
        // A new item goes in at the menu bar's left end, which on a full menu bar is behind the notch. macOS keeps each
        // item's place (points from the right edge) under this key once it's been dragged; until then Islet asks for a
        // spot near Control Center and the clock (RESEARCH.md "Menu bar position").
        let name = "IsletMenuBarItem"
        let position = "NSStatusItem Preferred Position \(name)"
        if UserDefaults.standard.object(forKey: position) == nil { UserDefaults.standard.set(Self.startPosition, forKey: position) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = name
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Peninsula")
        let menu = NSMenu()

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        let pause = menu.addItem(withTitle: "Pause Dynamic Peninsula", action: #selector(togglePause), keyEquivalent: "")
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
        menu.addItem(withTitle: "Quit Dynamic Peninsula", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // The menu opens from the click handler: in menu bar mode a plain click opens the island instead.
        statusMenu = menu
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        watchStatusIcon()
    }

    /// The pill, or the battery (DESIGN.md "Menu bar battery"), kept up to date with the charge.
    private func updateStatusIcon() {
        guard let item = statusItem, let button = item.button else { return }
        let s = power.state
        if MenuBarIconStyle.current == .battery, s.hasBattery {
            button.image = MenuBarBattery.image(percent: s.percent, charging: s.charging, onAC: s.onAC,
                                                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
            button.title = MenuBarBattery.showsPercent ? "\(s.percent)%" : ""
            button.imagePosition = MenuBarBattery.showsPercent ? .imageTrailing : .imageOnly
            item.length = NSStatusItem.variableLength
            button.toolTip = BatteryPage.status(s)
        } else {
            if batteryStats.isOpen { batteryStats.close() }
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Peninsula")
            button.title = ""
            button.imagePosition = .imageOnly
            item.length = NSStatusItem.squareLength
            button.toolTip = nil
        }
    }

    private func watchStatusIcon() {
        updateStatusIcon()
        watchStatusIconAgain()
        for path in [\UserDefaults.menuBarIconStyle, \UserDefaults.batteryIconPercent] as [KeyPath<UserDefaults, String?>] {
            iconObservers.append(UserDefaults.standard.observe(path, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.updateStatusIcon()
                    self?.applyMenuBarVisibility()
                    // Without a notch the island hangs under the icon, which just changed width.
                    self?.notch.screenChanged()
                }
            })
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusIcon() }
        }
        batteryStats.openControls = { [weak self] in self?.openControlCenter() }
    }

    /// Observation fires once per registration, so each change registers again.
    private func watchStatusIconAgain() {
        withObservationTracking { _ = power.state } onChange: {
            Task { @MainActor [weak self] in
                self?.updateStatusIcon()
                self?.watchStatusIconAgain()
            }
        }
    }

    /// The island's control center, opened from the battery icon.
    private func openControlCenter() {
        if notch.inMenuBar { notch.toggleFromMenuBar(); return }
        if notch.store.expanded { notch.store.collapse() } else { notch.store.expand() }
    }

    @objc private func statusItemClicked() {
        let e = NSApp.currentEvent
        let wantsMenu = e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true || e?.modifierFlags.contains(.option) == true
        if !wantsMenu, MenuBarIconStyle.current == .battery, power.state.hasBattery, let button = statusItem?.button {
            switch BatteryIconClick.current {
            case .stats: batteryStats.toggle(under: button)
            case .controls: openControlCenter()
            }
            return
        }
        if notch.inMenuBar && !wantsMenu {
            notch.toggleFromMenuBar()
            return
        }
        guard let item = statusItem, let menu = statusMenu else { return }
        batteryStats.close()
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
        let show = wanted || notch.store.geometry.map { $0.mode == .menuBar } ?? true || MenuBarIconStyle.current == .battery
        guard show != menuBarShown else { return }
        menuBarShown = show
        statusItem?.isVisible = show
    }

    #if DEBUG
    private var controlSpike: ControlSpike?
    private var bannerSpike: BannerSpike?
    private var messagesSpike: MessagesSpike?
    private var searchSpike: SearchSpike?
    @objc private func runSpike() {
        let s = ControlSpike(); controlSpike = s
        Task { await s.run() }
    }
    #endif

    @objc private func openSettings() { settings.show() }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem?.title = paused ? "Resume Dynamic Peninsula" : "Pause Dynamic Peninsula"
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
            for sector in EnrolmentEngine.order {
                model.snapshot.target = sector
                let a = Double(sector) * .pi / 2
                for step in 0..<20 {
                    let k = step < 10 ? Double(step) / 10 * 1.05 : Double(20 - step) / 10 * 1.05
                    model.snapshot.x = cos(a) * k
                    model.snapshot.y = sin(a) * k
                    if step == 10 { model.snapshot.filled[sector] = true }
                    try? await Task.sleep(for: .milliseconds(45))
                }
            }
            model.snapshot.target = nil
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
    /// KVO keys for the menu bar icon's look (`MenuBarIconStyle`, `MenuBarBattery.percentKey`).
    @objc dynamic var menuBarIconStyle: String? { string(forKey: "menuBarIconStyle") }
    @objc dynamic var batteryIconPercent: String? { object(forKey: "batteryIconPercent").map { "\($0)" } }
}
