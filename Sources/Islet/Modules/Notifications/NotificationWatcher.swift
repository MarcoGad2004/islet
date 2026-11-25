import AppKit
import ApplicationServices

/// Takes notification banners into the notch (DESIGN.md "Notifications", RESEARCH.md Q27-Q28).
///
/// Each banner arrives in Notification Center (`com.apple.notificationcenterui`) as a new window holding an
/// `AXNotificationCenterBanner` group with `title`, `subtitle` and `body` texts. The moment one is created it is moved
/// off screen, so only the notch shows it. It is left alive there so it still lands in Notification Center's list and
/// its own Show / Close can be pressed from the card. Only windows holding a banner are ever touched.
///
/// Incoming-call banners (`FACETIME_NOTIFICATION`) are left where they are: their Accept / Decline can't be pressed
/// from here (Q30).
@MainActor
final class NotificationWatcher {
    static let enabledKey = "notificationsInNotch"
    static let hideTextKey = "notificationsHideText"
    static let centerBundleID = "com.apple.notificationcenterui"

    var onNotification: ((NotificationItem) -> Void)?
    /// Whether the notch can take a banner right now (not locked, panel closed, island showing).
    var canTake: ((NotificationItem) -> Bool)?

    private var observer: AXObserver?
    private var pid: pid_t = 0
    private final class Banner {
        let window: AXUIElement
        let element: AXUIElement
        let origin: CGPoint?
        var restored = false
        init(window: AXUIElement, element: AXUIElement, origin: CGPoint?) {
            self.window = window; self.element = element; self.origin = origin
        }
    }
    private var banners: [UUID: Banner] = [:]
    private var retryTask: Task<Void, Never>?

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        // Notification Center restarts now and then (and on login): attach to the new process.
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == Self.centerBundleID else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
        attach()
    }

    /// Accessibility may be allowed later: try again then.
    func retry() { if observer == nil { attach() } }

    private func attach() {
        retryTask?.cancel()
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.centerBundleID).first else {
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.attach()
            }
            return
        }
        detach()
        pid = app.processIdentifier
        var obs: AXObserver?
        guard AXObserverCreate(pid, notificationCallback, &obs) == .success, let obs else { return }
        let root = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, root, kAXCreatedNotification as CFString, me)
        AXObserverAddNotification(obs, root, kAXLayoutChangedNotification as CFString, me)
        // Banners already up when Islet starts are left as they are.
        seen = AX.windows(ofApp: pid).flatMap { AX.all(in: $0, depth: 8, where: Self.isBanner) }
            .compactMap { AX.identifier($0) ?? AX.description($0) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        banners.removeAll()
        ownWindows.removeAll()
    }

    fileprivate func handle(_ element: AXUIElement, _ note: String) {
        if note == kAXUIElementDestroyedNotification as String {
            ownWindows.removeAll { CFEqual($0, element) }
            for (id, b) in banners where CFEqual(b.window, element) { banners[id] = nil }
            return
        }
        // A new banner window, or a banner added to one that is already up (macOS puts a second banner into the window
        // of the first, which may already be off screen): look for banners not seen yet.
        let created = note == kAXCreatedNotification as String && AX.role(element) == kAXWindowRole as String
        guard created || note == kAXLayoutChangedNotification as String else { return }
        sweep(extra: created ? element : nil, attempt: 0)
    }

    /// A banner, or several from one app that macOS has grouped (its texts are the newest one's).
    private static func isBanner(_ e: AXUIElement) -> Bool {
        let s = AX.subrole(e)
        return s == "AXNotificationCenterBanner" || s == "AXNotificationCenterBannerStack"
    }
    private static func isCall(_ e: AXUIElement) -> Bool {
        AX.identifier(e) == "FACETIME_NOTIFICATION" || AX.description(e) == "FaceTime Notification"
    }

    /// Banners already handled, by their identifier (a UUID per banner).
    private var seen: [String] = []
    /// Banner windows Islet has moved off screen; a later banner can land in one of them.
    private var ownWindows: [AXUIElement] = []

    /// Notification Center opened by the user arrives as a new window too, with banners in it. It is never touched:
    /// its list sits in an `AXNotificationListItems` group and it has a "Clear All" button, which a new banner window
    /// doesn't (its size is no help: banner windows span the screen, as they also host the desktop widgets).
    private static func isNotificationCenterList(_ w: AXUIElement) -> Bool {
        AX.first(in: w, depth: 8) {
            AX.identifier($0) == "AXNotificationListItems"
                || (AX.role($0) == kAXButtonRole as String && AX.description($0) == "Clear All")
        } != nil
    }

    private func sweep(extra: AXUIElement?, attempt: Int) {
        guard pid != 0 else { return }
        ownWindows.removeAll { !AX.alive($0) }
        var windows = ownWindows
        if let extra, !windows.contains(where: { CFEqual($0, extra) }), !Self.isNotificationCenterList(extra) {
            windows.append(extra)
        }
        var foundInExtra = false
        for w in windows {
            for banner in AX.all(in: w, depth: 8, where: Self.isBanner) {
                if let extra, CFEqual(w, extra) { foundInExtra = true }
                if Self.isCall(banner) { continue }
                let key = AX.identifier(banner) ?? AX.description(banner) ?? ""
                guard !key.isEmpty, !seen.contains(key) else { continue }
                seen.append(key)
                if seen.count > 100 { seen.removeFirst(50) }
                take(banner: banner, window: w)
            }
        }
        // A new window's banner is usually there at once; give it a moment if not.
        if let extra, !foundInExtra, attempt < 6 {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(25))
                self?.sweep(extra: extra, attempt: attempt + 1)
            }
        }
    }

    private func take(banner: AXUIElement, window: AXUIElement) {
        guard enabled, let item = read(banner), canTake?(item) == true else { return }
        // Where macOS put the window: kept from an earlier banner if this window is already off screen.
        let known = banners.values.first(where: { CFEqual($0.window, window) })?.origin
        let origin = known ?? AX.position(window)
        AX.setPosition(window, CGPoint(x: -3000, y: -3000))
        if !ownWindows.contains(where: { CFEqual($0, window) }) { ownWindows.append(window) }
        let b = Banner(window: window, element: banner, origin: origin)
        banners[item.id] = b
        watchDestroyed(window)
        // It fades in where macOS put it: keep it away while it settles.
        for ms in [40, 120, 300, 600] {
            Task { [weak self, weak b] in
                try? await Task.sleep(for: .milliseconds(ms))
                guard self != nil, let b, !b.restored else { return }
                AX.setPosition(b.window, CGPoint(x: -3000, y: -3000))
            }
        }
        onNotification?(item)
    }

    private func watchDestroyed(_ window: AXUIElement) {
        guard let observer else { return }
        AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
    }

    private func read(_ banner: AXUIElement) -> NotificationItem? {
        func text(_ id: String) -> String? {
            AX.first(in: banner, depth: 4) { AX.identifier($0) == id }.flatMap { AX.string($0, kAXValueAttribute) }
        }
        let title = text("title") ?? ""
        let subtitle = text("subtitle")
        let body = text("body") ?? ""
        guard !title.isEmpty || !body.isEmpty else { return nil }
        // The description is "App, Title, Subtitle, Body".
        var desc = AX.description(banner) ?? ""
        if desc.hasSuffix(", stacked") { desc = String(desc.dropLast(", stacked".count)) }
        var app = desc
        if !title.isEmpty, let r = desc.range(of: ", \(title)") { app = String(desc[..<r.lowerBound]) }
        else if let r = desc.range(of: ", ") { app = String(desc[..<r.lowerBound]) }
        let found = Self.app(named: app)
        // The app's own buttons: the named actions besides the ones every banner has.
        let common: Set<String> = ["Show", "Show Details", "Show More", "Close", "Clear All"] // "Show More" only expands the banner
        let actions = AX.actions(banner).filter { $0.hasPrefix("Name:") }.map { String($0.dropFirst(5)) }.filter { !common.contains($0) }
        let header = text("header") ?? ""
        return NotificationItem(id: UUID(), app: app, title: title, subtitle: subtitle, body: body, icon: found.icon, appURL: found.url,
                                actions: actions, timeSensitive: header.localizedCaseInsensitiveContains("time sensitive"),
                                fromIPhone: desc.hasSuffix(", from iPhone"))
    }

    /// The app by its shown name: running, or in the usual folders.
    private static func app(named name: String) -> (url: URL?, icon: NSImage?) {
        guard !name.isEmpty else { return (nil, nil) }
        // Only real apps: "running applications" also lists widget extensions, XPC services and daemons, some named like
        // an app ("Messages", "Podcasts"), and a match on one of those gave the generic "exec" icon (1.7.1: an iPhone
        // notification from "Apple Card" showed it). No app found means the iPhone glyph for iPhone notifications.
        if let r = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name && $0.bundleURL?.pathExtension == "app" }) {
            return (r.bundleURL, r.icon)
        }
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        for d in dirs {
            let path = "\(d)/\(name).app"
            if FileManager.default.fileExists(atPath: path) {
                return (URL(fileURLWithPath: path), NSWorkspace.shared.icon(forFile: path))
            }
        }
        return (nil, nil)
    }

    // MARK: Actions from the card

    /// Clicked: the banner's own Show, so it opens just as the real one would; the app if the banner is gone.
    func show(_ item: NotificationItem) {
        let b = banners.removeValue(forKey: item.id)
        if let b, AX.alive(b.element), AX.press(b.element, named: "Show") || AX.press(b.element) { return }
        if let url = item.appURL { NSWorkspace.shared.open(url) }
    }

    /// One of the banner's own buttons (Approve, Deny…): presses it on the banner, as its Options menu would.
    func perform(_ item: NotificationItem, action: String) {
        guard let b = banners.removeValue(forKey: item.id), AX.alive(b.element) else { return }
        AX.press(b.element, named: action)
    }

    /// Closed (Close, or swiped up).
    func close(_ item: NotificationItem) {
        guard let b = banners.removeValue(forKey: item.id), AX.alive(b.element) else { return }
        AX.press(b.element, named: "Close")
    }

    /// The card timed out. A banner goes by itself by then; one still there a moment later is an alert (it waits to
    /// be answered), so it goes back where macOS put it.
    func expired(_ item: NotificationItem) {
        guard let b = banners[item.id] else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self else { return }
            self.banners[item.id] = nil
            guard AX.alive(b.window), let origin = b.origin else { return }
            b.restored = true
            AX.setPosition(b.window, origin)
        }
    }
}

private let notificationCallback: AXObserverCallback = { _, element, note, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = note as String
    nonisolated(unsafe) let el = element
    MainActor.assumeIsolated { watcher.handle(el, name) }
}
