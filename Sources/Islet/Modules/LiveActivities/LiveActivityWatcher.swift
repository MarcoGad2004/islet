import AppKit
import ApplicationServices

/// One Live Activity from the iPhone (DESIGN.md "iPhone Live Activities"), read through Accessibility.
struct LiveActivity: Equatable, Identifiable {
    /// The app's name and its place among the activities ("Cadence#0").
    let id: String
    var app: String
    /// The right-hand side when it is text (a timer, a score, an ETA), as the menu bar shows it right now.
    var value: String?
    var icon: NSImage?
    /// The system's expanded card, read when the panel opens.
    var card: Card?
    /// When Islet first saw it (the newest shows in the compact shapes).
    var since: Date

    struct Card: Equatable {
        var title: String
        /// A short all-capitals word ("OVERDUE", "LIVE").
        var flag: String?
        var lines: [String]
        var buttons: [String]
    }

    static func == (a: LiveActivity, b: LiveActivity) -> Bool {
        a.id == b.id && a.app == b.app && a.value == b.value && a.card == b.card && a.since == b.since && (a.icon == nil) == (b.icon == nil)
    }
}

/// Watches `MenuBarAgent` for the Live Activities macOS 26 shows from the iPhone (RESEARCH.md Q47-Q52). Each is a menu
/// bar item with the subrole `AXLiveActivity`; its sides and its card are read through Accessibility.
///
/// macOS sends no change notification for an activity's own text, so while one is up its value is read once a second.
/// New ones are noticed from `MenuBarAgent`'s created / layout notifications, with a check every 5 s as a fallback.
@MainActor
final class LiveActivityWatcher {
    static let enabledKey = "liveActivitiesInNotch"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Called whenever the list or a value changes.
    var onChange: (([LiveActivity]) -> Void)?
    private(set) var activities: [LiveActivity] = []

    private var pid: pid_t = 0
    private var app: AXUIElement?
    private var observer: AXObserver?
    private var timer: Timer?
    private var firstSeen: [String: Date] = [:]
    private var cards: [String: LiveActivity.Card] = [:]
    private var iconCache: [String: NSImage?] = [:]
    private var launchObserver: NSObjectProtocol?

    func start() {
        attach()
        // MenuBarAgent restarting (or starting late): attach again.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == "com.apple.MenuBarAgent" else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
        schedule()
    }

    func refreshNow() { poll() }

    private func attach() {
        guard AXIsProcessTrusted(),
              let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return }
        pid = agent.processIdentifier
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.25)
        app = el
        var obs: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<LiveActivityWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.structureChanged() }
        }, &obs) == .success, let obs else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(obs, el, n as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        poll()
    }

    /// Something in MenuBarAgent was added or removed: look again, but only now and then (the clock ticks it too).
    private var lastStructureCheck = Date.distantPast
    private func structureChanged() {
        guard activities.isEmpty, Date().timeIntervalSince(lastStructureCheck) > 0.5 else { return }
        lastStructureCheck = Date()
        poll()
    }

    /// Once a second while an activity is up (its value); every 5 s otherwise, as a fallback for a missed notification.
    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: activities.isEmpty ? 5 : 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Reading

    private func items() -> [AXUIElement] {
        guard let app, let bar = AX.element(app, "AXExtrasMenuBar") else { return [] }
        return AX.children(bar).filter { AX.subrole($0) == "AXLiveActivity" }
    }

    private func poll() {
        guard Self.enabled, AXIsProcessTrusted() else {
            if !activities.isEmpty { activities = []; onChange?([]); schedule() }
            return
        }
        if app == nil { attach() }
        var seenCount: [String: Int] = [:]
        var next: [LiveActivity] = []
        for item in items() {
            let name = AX.description(item) ?? "Live Activity"
            let n = seenCount[name, default: 0]
            seenCount[name] = n + 1
            let id = "\(name)#\(n)"
            let since = firstSeen[id] ?? Date()
            firstSeen[id] = since
            next.append(LiveActivity(id: id, app: name, value: Self.trailingText(item), icon: icon(for: name), card: cards[id], since: since))
        }
        firstSeen = firstSeen.filter { k, _ in next.contains { $0.id == k } }
        cards = cards.filter { k, _ in next.contains { $0.id == k } }
        let wasEmpty = activities.isEmpty
        if next != activities {
            activities = next
            onChange?(next)
        }
        if wasEmpty != next.isEmpty { schedule() }
    }

    /// The right-hand side: the last group's text, when it has any.
    private static func trailingText(_ item: AXUIElement) -> String? {
        let groups = AX.children(item).filter { AX.role($0) == kAXGroupRole as String }
        guard groups.count >= 2 else { return nil }
        var found: String?
        AX.walk(groups[groups.count - 1], depth: 4) { e in
            if found == nil, AX.role(e) == kAXStaticTextRole as String, let v = AX.string(e, kAXValueAttribute), !v.isEmpty { found = v }
        }
        return found
    }

    /// The Mac app of the same name, when there is one ("Cadence" finds CadenceMac too).
    private func icon(for name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", fm.homeDirectoryForCurrentUser.path + "/Applications"]
        var found: NSImage?
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            let n = $0.localizedName ?? ""
            return n == name || n == name + "Mac" || n == name + " for Mac"
        }), let url = running.bundleURL {
            found = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            for d in dirs {
                for candidate in [name, name + "Mac", name + " for Mac"] where fm.fileExists(atPath: "\(d)/\(candidate).app") {
                    found = NSWorkspace.shared.icon(forFile: "\(d)/\(candidate).app")
                    break
                }
                if found != nil { break }
            }
        }
        iconCache[name] = found
        return found
    }

    // MARK: The card

    /// Reads each activity's expanded card (the panel opening): opens the system's card, moves it off screen, reads its
    /// text and buttons, and closes it again (RESEARCH.md Q49, Q52).
    func readCards() {
        guard Self.enabled, AXIsProcessTrusted() else { return }
        Task { @MainActor in
            for (i, item) in items().enumerated() where i < activities.count {
                let id = activities[i].id
                guard let window = await openCard(item) else { continue }
                if let card = Self.parse(window, value: activities[i].value) {
                    cards[id] = card
                    activities[i].card = card
                    onChange?(activities)
                }
                closeCard(item)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    /// Presses one of the card's own buttons ("Complete"): opens the card off screen, presses it, closes the card.
    func press(_ button: String, on activityID: String) {
        guard let i = activities.firstIndex(where: { $0.id == activityID }) else { return }
        let all = items()
        guard i < all.count else { return }
        let item = all[i]
        Task { @MainActor in
            guard let window = await openCard(item) else { return }
            var target: AXUIElement?
            AX.walk(window, depth: 8) { e in
                if target == nil, AX.role(e) == kAXButtonRole as String, AX.description(e) == button { target = e }
            }
            if let target { AXUIElementPerformAction(target, kAXPressAction as CFString) }
            try? await Task.sleep(for: .milliseconds(250))
            if self.cardWindow() != nil { closeCard(item) }
            self.cards[activityID] = nil
            self.poll()
        }
    }

    private static let offScreen = CGPoint(x: -4000, y: -4000)

    /// Presses the item and keeps its card off screen: macOS places the card itself just after creating it, so the move
    /// is repeated until it stays (Q52).
    private func openCard(_ item: AXUIElement) async -> AXUIElement? {
        if let open = cardWindow() { return open }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        for _ in 0..<30 {
            if let w = cardWindow() {
                for _ in 0..<12 {
                    moveOff(w)
                    try? await Task.sleep(for: .milliseconds(15))
                    if let f = AX.frame(w), f.origin.x < -1000 { break }
                }
                // Let its content arrive.
                try? await Task.sleep(for: .milliseconds(60))
                return w
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private func moveOff(_ w: AXUIElement) {
        var p = Self.offScreen
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) }
    }

    /// Pressing the item again closes its card (Esc doesn't reliably).
    private func closeCard(_ item: AXUIElement) {
        guard cardWindow() != nil else { return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }

    private func cardWindow() -> AXUIElement? {
        guard let app else { return nil }
        return AX.children(app, kAXWindowsAttribute).first { AX.identifier($0) == "live-activity-expanded" }
    }

    /// Lays the card's texts out the way the design says: the first is the title, a short all-capitals word the flag, the
    /// value (shown live from the menu bar instead) dropped, the rest lines. Tiny texts are a symbol's label.
    static func parse(_ window: AXUIElement, value: String?) -> LiveActivity.Card? {
        var texts: [String] = []
        var buttons: [String] = []
        AX.walk(window, depth: 10) { e in
            let role = AX.role(e)
            if role == kAXButtonRole as String, let d = AX.description(e), !d.isEmpty { buttons.append(d) }
            if role == kAXStaticTextRole as String, let v = AX.string(e, kAXValueAttribute), !v.isEmpty {
                if let f = AX.frame(e), f.width < 8 { return } // a symbol's label ("!")
                if texts.last != v { texts.append(v) }
            }
        }
        return card(texts: texts, buttons: buttons, value: value)
    }

    nonisolated static func card(texts: [String], buttons: [String], value: String?) -> LiveActivity.Card? {
        var rest = texts.filter { $0 != value && !isValue($0) }
        guard !rest.isEmpty else { return nil }
        var flag: String?
        if let i = rest.firstIndex(where: isFlag) { flag = rest.remove(at: i) }
        guard !rest.isEmpty else { return nil }
        let title = rest.removeFirst()
        return LiveActivity.Card(title: title, flag: flag, lines: rest, buttons: buttons)
    }

    /// "1:37:23", "12:04", "98–101": the value, which the card shows live from the menu bar.
    nonisolated static func isValue(_ s: String) -> Bool {
        s.range(of: #"^\d{1,2}(:\d{2}){1,2}$"#, options: .regularExpression) != nil
    }

    /// "OVERDUE", "LIVE", "ETA": short, all capitals, letters only.
    nonisolated static func isFlag(_ s: String) -> Bool {
        s.count >= 2 && s.count <= 12 && s == s.uppercased() && s.allSatisfy { $0.isLetter || $0 == " " } && s.contains(where: \.isLetter)
    }
}

extension AX {
    /// An element held in an attribute ("AXExtrasMenuBar").
    static func element(_ e: AXUIElement, _ a: String) -> AXUIElement? {
        guard let v = attr(e, a), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    /// The elements in a list attribute (windows, children).
    static func children(_ e: AXUIElement, _ a: String) -> [AXUIElement] { (attr(e, a) as? [AXUIElement]) ?? [] }

    /// Every element down to `depth`, the element itself first.
    static func walk(_ e: AXUIElement, depth: Int, _ visit: (AXUIElement) -> Void) {
        visit(e)
        guard depth > 0 else { return }
        for c in children(e) { walk(c, depth: depth - 1, visit) }
    }

    static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }
}
