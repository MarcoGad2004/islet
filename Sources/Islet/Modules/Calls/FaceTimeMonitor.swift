import AppKit
import ApplicationServices

/// A FaceTime call for the notch (DESIGN.md "Calls", RESEARCH.md Q30-Q31).
///
/// Ringing comes from the call's notification banner (`NotificationWatcher.onRinging`). In the call, FaceTime's window
/// has the other person's name (`AvatarView`, or the participant button), the camera and microphone switches
/// (`toggleVideoButton`, `toggleMicMenuButton`, value 1 = on) and End (`leaveButton`), all pressable. When its controls
/// are hidden only `ParticipantGridView` is there; pressing it brings them back.
///
/// Nothing runs while FaceTime is closed. While it is open, its window changes are observed; during a call it is also
/// re-read every 2 s (mute and the name don't always post a change).
@MainActor
final class FaceTimeMonitor {
    static let bundleID = "com.apple.FaceTime"

    var onChange: ((CallState?) -> Void)?
    private(set) var state: CallState?

    private var ringing = false
    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var scanTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.detach(); self?.update(nil) }
        }
        attach()
    }

    func retry() { if observer == nil { attach() } }

    /// The call banner came or went. When it goes the call was answered (FaceTime opens) or not: look again shortly.
    func setRinging(_ on: Bool) {
        ringing = on
        if on {
            if state?.phase != .active { update(CallState(phase: .ringing)) }
        } else {
            if state?.phase == .ringing { update(nil) }
            attach()
            for s in [0.4, 1.2, 2.5, 5.0] { scheduleScan(after: s) }
        }
    }

    private func attach() {
        guard observer == nil, AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return }
        pid = app.processIdentifier
        var obs: AXObserver?
        guard AXObserverCreate(pid, faceTimeCallback, &obs) == .success, let obs else { return }
        let root = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXValueChangedNotification,
                  kAXTitleChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(obs, root, n as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
        scheduleScan(after: 0.1)
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        pid = 0
        pollTask?.cancel(); pollTask = nil
    }

    fileprivate func changed() { scheduleScan(after: 0.15) }

    private func scheduleScan(after seconds: Double) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    /// FaceTime's call window, if a call is up.
    private func callWindow() -> AXUIElement? {
        guard pid != 0 else { return nil }
        for w in AX.windows(ofApp: pid) {
            if AX.first(in: w, id: "ParticipantGridView") != nil || AX.first(in: w, id: "leaveButton") != nil { return w }
        }
        return nil
    }

    private func scan() {
        guard let w = callWindow() else {
            if state?.phase == .active { update(ringing ? CallState(phase: .ringing) : nil) }
            pollTask?.cancel(); pollTask = nil
            return
        }
        var next = state?.phase == .active ? state! : CallState(phase: .active)
        let avatar = AX.first(in: w, id: "AvatarView").flatMap { AX.description($0) }
        let connecting = avatar?.hasPrefix("Connecting") == true || avatar?.hasSuffix("…") == true
        // The participant button carries the name; once connected `AvatarView` reads "￼ FaceTime Video" instead.
        if let b = AX.first(in: w, where: { AX.role($0) == kAXButtonRole as String && AX.identifier($0) == nil
                                           && AX.actions($0).contains("Name:Take Live Photo") }),
           let n = AX.description(b) {
            next.name = n
        } else if let avatar, !connecting, !avatar.contains("\u{FFFC}"), !avatar.hasPrefix("FaceTime") {
            next.name = avatar
        }
        if !connecting && next.connectedAt == nil { next.connectedAt = Date() }
        if let mic = AX.first(in: w, id: "toggleMicMenuButton").flatMap({ AX.number($0, kAXValueAttribute) }) { next.muted = mic == 0 }
        if let cam = AX.first(in: w, id: "toggleVideoButton").flatMap({ AX.number($0, kAXValueAttribute) }) { next.cameraOn = cam != 0 }
        if let grid = AX.first(in: w, id: "ParticipantGridView").flatMap({ AX.description($0) }) {
            next.video = !grid.localizedCaseInsensitiveContains("audio")
        }
        update(next)
        if pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.scan()
                }
            }
        }
    }

    private func update(_ s: CallState?) {
        guard s != state else { return }
        state = s
        onChange?(s)
    }

    // MARK: Controls (the call page)

    func toggleMute() { press("toggleMicMenuButton") }
    func toggleCamera() { press("toggleVideoButton") }
    func end() { press("leaveButton") }

    /// Presses one of FaceTime's call controls, first bringing them back if they are hidden.
    private func press(_ id: String) {
        guard let w = callWindow() else { return }
        if let b = AX.first(in: w, id: id) {
            AX.press(b)
            scheduleScan(after: 0.3)
            return
        }
        if let grid = AX.first(in: w, id: "ParticipantGridView") { AX.press(grid) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, let w = self.callWindow(), let b = AX.first(in: w, id: id) else { return }
            AX.press(b)
            self.scheduleScan(after: 0.3)
        }
    }
}

private let faceTimeCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let monitor = Unmanaged<FaceTimeMonitor>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.changed() }
}
