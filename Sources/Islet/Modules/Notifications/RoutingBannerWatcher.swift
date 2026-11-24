import AppKit
import ApplicationServices

/// Keeps the AirPods "Connected" card out of the top-right corner, so a device connecting to this Mac shows only in the
/// notch (RESEARCH.md Q22).
///
/// The card is not a notification: `com.apple.MenuBarAgent` opens a window identified `smart-routing-system-banner`
/// holding the device's name and the status. A card saying the device connected is moved off screen the moment it is
/// created, and kept there until it closes by itself. Every other card (such as "Moved to iPhone") is left alone, as
/// are all other windows. When the notch can't show the event (panel open, locked) the card stays where macOS put it.
@MainActor
final class RoutingBannerWatcher {
    nonisolated static let agentBundleID = "com.apple.MenuBarAgent"
    static let bannerID = "smart-routing-system-banner"

    /// A device connected (its name). Returns whether the notch shows it; if not, the card stays.
    var onConnected: ((_ name: String) -> Bool)?
    var enabled: () -> Bool = { true }

    private var observer: AXObserver?
    private var retryTask: Task<Void, Never>?

    func start() {
        // The diagnostics file 1.6's test builds kept while hiding was tuned: nothing writes it any more.
        try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Islet-airpods-card.log"))
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == Self.agentBundleID else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
        attach()
    }

    /// Accessibility may be allowed later: try again then.
    func retry() { if observer == nil { attach() } }

    private func attach() {
        retryTask?.cancel()
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.agentBundleID).first else {
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.attach()
            }
            return
        }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        var obs: AXObserver?
        guard AXObserverCreate(app.processIdentifier, routingCallback, &obs) == .success, let obs else { return }
        AXObserverAddNotification(obs, AXUIElementCreateApplication(app.processIdentifier), kAXCreatedNotification as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
    }

    fileprivate func created(_ window: AXUIElement) {
        guard AX.role(window) == kAXWindowRole as String else { return }
        look(at: window, attempt: 0)
    }

    /// Whether the card's status says the device connected (to this Mac), not that it moved away.
    static func isConnect(_ status: String) -> Bool {
        let s = status.lowercased()
        return s.contains("connected") && !s.contains("disconnected") && !s.contains("moved")
    }

    /// The card's texts are there as the window is created; give them a moment if not.
    private func look(at window: AXUIElement, attempt: Int) {
        guard AX.identifier(window) == Self.bannerID else { return }
        let texts = AX.all(in: window, depth: 6) { AX.role($0) == kAXStaticTextRole as String }
            .compactMap { AX.string($0, kAXValueAttribute) }.filter { !$0.isEmpty }
        guard texts.count >= 2 else {
            if attempt < 8 {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(25))
                    self?.look(at: window, attempt: attempt + 1)
                }
            }
            return
        }
        let origin = AX.position(window)
        // Name first, then the texts: a "Connected" card also has the battery ("41") between them.
        guard enabled(), texts.dropFirst().contains(where: Self.isConnect) else { return }
        AX.setPosition(window, CGPoint(x: -3000, y: -3000))
        guard onConnected?(texts[0]) == true else {
            if let origin { AX.setPosition(window, origin) }
            return
        }
        keepAway(window)
    }

    /// MenuBarAgent may place the card again as it animates in: keep it off screen until it closes (at most 10 s).
    /// Off the main thread: each check is a round trip to MenuBarAgent, 60 times a second while the notch animates the
    /// connection, and on the main thread they made that animation stutter.
    private func keepAway(_ window: AXUIElement) {
        nonisolated(unsafe) let window = window
        Task.detached(priority: .userInitiated) {
            let start = Date()
            while Date().timeIntervalSince(start) < 10, AX.alive(window) {
                if let p = AX.position(window), p.x > -2000 { AX.setPosition(window, CGPoint(x: -3000, y: -3000)) }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

private let routingCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<RoutingBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let el = element
    MainActor.assumeIsolated { watcher.created(el) }
}
