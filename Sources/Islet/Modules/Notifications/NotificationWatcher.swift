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
/// from here (Q30). They are reported as ringing instead.
@MainActor
final class NotificationWatcher {
    static let enabledKey = "notificationsInNotch"
    static let hideTextKey = "notificationsHideText"
    static let centerBundleID = "com.apple.notificationcenterui"

    var onNotification: ((NotificationItem) -> Void)?
    /// A FaceTime (or relayed iPhone) call's banner came up (true) or went away (false).
    var onRinging: ((Bool) -> Void)?
    /// Whether the notch can take a banner right now (not locked, panel closed, island showing).
    var canTake: (() -> Bool)?

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
    private var ringWindow: AXUIElement?
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
        AXObserverAddNotification(obs, root, kAXCreatedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        banners.removeAll()
        if ringWindow != nil { ringWindow = nil; onRinging?(false) }
    }

    fileprivate func handle(_ element: AXUIElement, _ note: String) {
        if note == kAXUIElementDestroyedNotification as String {
            if let ring = ringWindow, CFEqual(ring, element) { ringWindow = nil; onRinging?(false) }
            if let (id, _) = banners.first(where: { CFEqual($0.value.window, element) }) { banners[id] = nil }
            return
        }
        guard note == kAXCreatedNotification as String, AX.role(element) == kAXWindowRole as String else { return }
        take(window: element, attempt: 0)
    }

    private static func bannerElement(in window: AXUIElement) -> AXUIElement? {
        AX.first(in: window, depth: 8) { AX.subrole($0) == "AXNotificationCenterBanner" }
    }

    private func take(window: AXUIElement, attempt: Int) {
        // The banner group is usually there when the window is created; give it a moment if not.
        guard let banner = Self.bannerElement(in: window) else {
            if attempt < 6 {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(25))
                    self?.take(window: window, attempt: attempt + 1)
                }
            }
            return
        }
        if AX.identifier(banner) == "FACETIME_NOTIFICATION" || AX.description(banner) == "FaceTime Notification" {
            guard ringWindow == nil || !CFEqual(ringWindow!, window) else { return }
            ringWindow = window
            watchDestroyed(window)
            onRinging?(true)
            return
        }
        guard enabled, canTake?() == true else { return }
        let origin = AX.position(window)
        AX.setPosition(window, CGPoint(x: -3000, y: -3000))
        guard let item = read(banner) else {
            if let origin { AX.setPosition(window, origin) } // nothing to show: give it back
            return
        }
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
        let desc = AX.description(banner) ?? ""
        var app = desc
        if !title.isEmpty, let r = desc.range(of: ", \(title)") { app = String(desc[..<r.lowerBound]) }
        else if let r = desc.range(of: ", ") { app = String(desc[..<r.lowerBound]) }
        let found = Self.app(named: app)
        return NotificationItem(id: UUID(), app: app, title: title, subtitle: subtitle, body: body, icon: found.icon, appURL: found.url)
    }

    /// The app by its shown name: running, or in the usual folders.
    private static func app(named name: String) -> (url: URL?, icon: NSImage?) {
        guard !name.isEmpty else { return (nil, nil) }
        if let r = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name && $0.bundleURL != nil }) {
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
