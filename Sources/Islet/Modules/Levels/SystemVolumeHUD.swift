import AppKit
import ApplicationServices

/// Hides macOS's own volume display for changes Islet can't catch as a key (AirPods' controls; DESIGN.md "Volume and
/// brightness"). Since macOS 27 it is a window of MenuBarAgent with the identifier `volume-system-banner`, at the top
/// right. The moment one is created it is moved far off screen, as notification banners are, so only the notch shows
/// the change. Nothing else of MenuBarAgent's is touched. Needs Accessibility.
@MainActor
final class SystemVolumeHUD {
    nonisolated static let bundleID = "com.apple.MenuBarAgent"
    private static let identifier = "volume-system-banner"
    private static let parked = CGPoint(x: -20000, y: -20000)

    /// Whether to hide it now (the island shows volume: Settings > Features).
    var shouldHide: () -> Bool = { true }

    private var observer: AXObserver?
    private var pid: pid_t = 0
    /// Volume windows seen and still alive: macOS reuses one while it shows, and may put it back.
    private var windows: [AXUIElement] = []
    private var launchObserver: NSObjectProtocol?

    func start() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
        attach()
    }

    /// Accessibility allowed later, or MenuBarAgent wasn't running yet.
    func retry() { if observer == nil { attach() } }

    private func attach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; windows.removeAll()
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return }
        pid = app.processIdentifier
        var obs: AXObserver?
        guard AXObserverCreate(pid, systemVolumeHUDCallback, &obs) == .success, let obs else { return }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.25)
        let me = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, root, kAXWindowCreatedNotification as CFString, me)
        AXObserverAddNotification(obs, root, kAXCreatedNotification as CFString, me)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
    }

    fileprivate func created(_ element: AXUIElement) {
        guard AX.role(element) == kAXWindowRole as String, AX.identifier(element) == Self.identifier else { return }
        if !windows.contains(where: { CFEqual($0, element) }) { windows.append(element) }
        park()
    }

    /// Moves the volume window away now and a few times as it settles (the first move, as it is made, doesn't hold).
    /// Also called on every volume change from elsewhere, as macOS brings a reused window back.
    func park() {
        windows.removeAll { !AX.alive($0) }
        guard shouldHide(), !windows.isEmpty else { return }
        for w in windows { AX.setPosition(w, Self.parked) }
        for ms in [30, 100, 250, 500] {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(ms))
                guard let self, self.shouldHide() else { return }
                for w in self.windows where AX.alive(w) {
                    if let p = AX.position(w), p != Self.parked { AX.setPosition(w, Self.parked) }
                }
            }
        }
    }
}

private let systemVolumeHUDCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon else { return }
    let hud = Unmanaged<SystemVolumeHUD>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let el = element
    MainActor.assumeIsolated { hud.created(el) }
}
