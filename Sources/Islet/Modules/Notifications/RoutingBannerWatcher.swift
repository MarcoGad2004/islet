import AppKit
import ApplicationServices

/// Tells the notch when AirPods or another device connect, from the macOS "Connected" card (RESEARCH.md Q22). The card
/// is the only sign when AirPods switch back from an iPhone: IOBluetooth reports no connect then.
///
/// The card is not a notification: `com.apple.MenuBarAgent` opens a window identified `smart-routing-system-banner`
/// holding the device's name and the status. Only cards saying the device connected count; others (such as "Moved to
/// iPhone") are ignored. The card itself stays: MenuBarAgent puts it back every frame when it's moved (1.6 test
/// builds, 2026-11-24), so it can't be hidden.
@MainActor
final class RoutingBannerWatcher {
    nonisolated static let agentBundleID = "com.apple.MenuBarAgent"
    static let bannerID = "smart-routing-system-banner"

    /// A device connected (its name).
    var onConnected: ((_ name: String) -> Void)?
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
        // Name first, then the texts: a "Connected" card also has the battery ("41") between them.
        guard enabled(), texts.dropFirst().contains(where: Self.isConnect) else { return }
        onConnected?(texts[0])
    }
}

private let routingCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<RoutingBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let el = element
    MainActor.assumeIsolated { watcher.created(el) }
}
