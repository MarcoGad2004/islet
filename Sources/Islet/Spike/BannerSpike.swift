#if DEBUG
import AppKit
import ApplicationServices
import IOBluetooth

/// Spike: which process draws the AirPods "Connected" / "Moved to iPhone" cards, and can it be read and moved like a
/// notification banner (RESEARCH.md Q22, Q27)? Read-only: nothing is moved or closed.
/// `-IsletDebugShape bannerspike` watches for 4 minutes; log at ~/Library/Logs/Islet-banner-spike.log.
@MainActor
final class BannerSpike: NSObject {
    private let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-banner-spike.log")
    private let start = Date()
    private var known: Set<Int> = []
    private var btNote: IOBluetoothUserNotification?
    private var disconnectNotes: [IOBluetoothUserNotification] = []
    private var observers: [pid_t: AXObserver] = [:]

    private func log(_ s: String) {
        let line = String(format: "%7.2f  ", Date().timeIntervalSince(start)) + s + "\n"
        print(line, terminator: "")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    }

    func run(minutes: Double = 3) async {
        try? "".write(to: url, atomically: true, encoding: .utf8)
        log("# banner spike \(Date())  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)  AX trusted=\(AXIsProcessTrusted())")
        known = Set(windows().map(\.id))
        btNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] {
            if let n = d.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:))) { disconnectNotes.append(n) }
        }
        // AXCreated on the system UI processes that could draw the card.
        let candidates = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return id.hasPrefix("com.apple.") && ["MenuBarAgent", "notificationcenterui", "controlcenter", "BluetoothUIServer", "systemuiserver",
                    "UserNotificationCenter", "BluetoothUIService", "SystemUIServer", "WindowManager"].contains { id.localizedCaseInsensitiveContains($0) }
        }
        log("watching AX of: " + candidates.map { "\($0.bundleIdentifier ?? "?")(\($0.processIdentifier))" }.joined(separator: ", "))
        for app in candidates { observe(app.processIdentifier) }
        let end = Date().addingTimeInterval(minutes * 60)
        while Date() < end {
            poll()
            try? await Task.sleep(for: .milliseconds(80))
        }
        log("done")
        NSApp.terminate(nil)
    }

    private struct Win { let id: Int; let owner: String; let pid: pid_t; let layer: Int; let bounds: CGRect; let name: String }

    private func windows() -> [Win] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { d in
            guard let id = d[kCGWindowNumber as String] as? Int else { return nil }
            var r = CGRect.zero
            if let b = d[kCGWindowBounds as String] as? NSDictionary { r = CGRect(dictionaryRepresentation: b) ?? .zero }
            return Win(id: id, owner: d[kCGWindowOwnerName as String] as? String ?? "?",
                       pid: d[kCGWindowOwnerPID as String] as? pid_t ?? 0, layer: d[kCGWindowLayer as String] as? Int ?? 0,
                       bounds: r, name: d[kCGWindowName as String] as? String ?? "")
        }
    }

    /// New on-screen windows from any process that are not ordinary app windows (layer 0).
    private func poll() {
        for w in windows() where !known.contains(w.id) {
            known.insert(w.id)
            guard w.layer != 0 else { continue }
            let bundle = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? "?"
            log("WINDOW +\(w.id) owner=\(w.owner) [\(bundle)] pid=\(w.pid) layer=\(w.layer) frame=\(w.bounds) name='\(w.name)'")
        }
    }

    private func observe(_ pid: pid_t) {
        var obs: AXObserver?
        guard AXObserverCreate(pid, spikeCallback, &obs) == .success, let obs else { log("AXObserverCreate failed for \(pid)"); return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let root = AXUIElementCreateApplication(pid)
        let r = AXObserverAddNotification(obs, root, kAXCreatedNotification as CFString, me)
        AXObserverAddNotification(obs, root, kAXLayoutChangedNotification as CFString, me)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observers[pid] = obs
        if r != .success { log("AXCreated on \(pid): \(r.rawValue)") }
    }

    fileprivate func axEvent(_ e: AXUIElement, _ note: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(e, &pid)
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?"
        guard note == kAXCreatedNotification as String || AX.role(e) == kAXWindowRole as String else { return }
        log("AX \(note) in \(bundle): role=\(AX.role(e) ?? "-") subrole=\(AX.subrole(e) ?? "-") pos=\(AX.position(e).map { "\($0)" } ?? "-")")
        // The tree a moment later, once its content is in.
        Task { @MainActor in
            for ms in [0, 150, 600] {
                try? await Task.sleep(for: .milliseconds(ms))
                self.log("  tree after \(ms) ms:")
                self.dump(e, depth: 0)
            }
        }
    }

    private func dump(_ e: AXUIElement, depth: Int) {
        guard depth < 9 else { return }
        let pad = String(repeating: "  ", count: depth + 2)
        var bits = ["\(AX.role(e) ?? "-")"]
        if let s = AX.subrole(e) { bits.append("sub=\(s)") }
        if let s = AX.identifier(e) { bits.append("id=\(s)") }
        if let s = AX.description(e) { bits.append("desc='\(s)'") }
        if let s = AX.string(e, kAXTitleAttribute), !s.isEmpty { bits.append("title='\(s)'") }
        if let s = AX.string(e, kAXValueAttribute), !s.isEmpty { bits.append("value='\(s)'") }
        let acts = AX.actions(e)
        if !acts.isEmpty { bits.append("actions=\(acts)") }
        log(pad + bits.joined(separator: " "))
        for c in AX.children(e) { dump(c, depth: depth + 1) }
    }

    @objc nonisolated private func connected(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "?", c = device.isConnected()
        Task { @MainActor in self.log("BT connect callback: \(name) isConnected=\(c)") }
    }

    @objc nonisolated private func disconnected(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "?"
        Task { @MainActor in self.log("BT disconnect callback: \(name)") }
    }
}

private let spikeCallback: AXObserverCallback = { _, element, note, refcon in
    guard let refcon else { return }
    let spike = Unmanaged<BannerSpike>.fromOpaque(refcon).takeUnretainedValue()
    let name = note as String
    nonisolated(unsafe) let el = element
    MainActor.assumeIsolated { spike.axEvent(el, name) }
}
#endif
