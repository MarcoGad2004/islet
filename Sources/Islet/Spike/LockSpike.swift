#if DEBUG
import AppKit
@preconcurrency import AVFoundation
import Carbon.HIToolbox
import Vision

/// M2 feasibility spike for face unlock (docs/RESEARCH.md items 10-14). Throwaway, Debug builds only.
/// Turn it on from the menu bar item ("Face unlock spike"), lock the Mac (ctrl-cmd-Q), wait ~30 s, unlock,
/// then read ~/Library/Logs/Islet-M2-spike.log. It never types a password: only the letters z and q.
@MainActor
final class LockSpike {
    private let notch: NotchController
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var camera: CameraProbe?
    private var tasks: [Task<Void, Never>] = []
    private(set) var enabled = false

    init(notch: NotchController) { self.notch = notch }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on { start() } else { stop() }
    }

    private func start() {
        SpikeLog.write("=== spike armed. AXIsProcessTrusted=\(AXIsProcessTrusted()) camera=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue) ===")
        // Ask for camera access now, while unlocked, so the prompt is not hidden by the lock screen.
        AVCaptureDevice.requestAccess(for: .video) { granted in SpikeLog.write("camera access prompt result: \(granted)") }
        if !AXIsProcessTrusted() {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        let dnc = DistributedNotificationCenter.default()
        let ws = NSWorkspace.shared.notificationCenter
        func add(_ center: NotificationCenter, _ name: String, _ handler: @escaping @MainActor () -> Void) {
            let o = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SpikeLog.write("notification: \(name)"); handler() }
            }
            observers.append((center, o))
        }
        add(dnc, "com.apple.screenIsLocked") { [self] in locked() }
        add(dnc, "com.apple.screenIsUnlocked") { [self] in unlocked() }
        add(ws, NSWorkspace.screensDidSleepNotification.rawValue) {}
        add(ws, NSWorkspace.screensDidWakeNotification.rawValue) {}
        add(ws, NSWorkspace.sessionDidResignActiveNotification.rawValue) {}
        add(ws, NSWorkspace.sessionDidBecomeActiveNotification.rawValue) {}
    }

    private func stop() {
        for (c, o) in observers { c.removeObserver(o) }
        observers = []
        tasks.forEach { $0.cancel() }
        camera?.stop(); camera = nil
        SpikeLog.write("=== spike disarmed ===")
    }

    // MARK: Lock sequence

    private func locked() {
        tasks.forEach { $0.cancel() }
        // Q11/Q14: camera frames and face detection while locked.
        camera = CameraProbe()
        camera?.start()

        // Q13: show the scan shape at the normal level first, then at the shielding level.
        notch.store.setBase(.scan)
        notch.setDebugLevel(nil)
        logWindows("lock +0s (normal level)")

        tasks = [Task { [self] in
            await sleep(5)
            notch.setDebugLevel(NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())))
            SpikeLog.write("Q13: panel raised to shielding level (phase 2)")
            await sleep(0.5)
            logWindows("lock +5.5s (shielding level)")

            await sleep(5)
            SkyLightProbe.raise(window: notch.windowNumber)
            await sleep(0.5)
            logWindows("lock +10.5s (SkyLight space)")

            // Q12: keystrokes. Three z via the HID tap, then three q via the session tap.
            await sleep(5)
            SpikeLog.write("Q12: secureInput=\(IsSecureEventInputEnabled()) trusted=\(AXIsProcessTrusted())")
            post(key: CGKeyCode(kVK_ANSI_Z), tap: .cghidEventTap, count: 3)
            SpikeLog.write("Q12: posted 3x z via cghidEventTap")
            await sleep(4)
            post(key: CGKeyCode(kVK_ANSI_Q), tap: .cgSessionEventTap, count: 3)
            SpikeLog.write("Q12: posted 3x q via cgSessionEventTap")
        }]
    }

    private func unlocked() {
        tasks.forEach { $0.cancel() }
        camera?.stop(); camera = nil
        notch.setDebugLevel(nil)
        notch.store.setBase(nil)
    }

    private func sleep(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    private func post(key: CGKeyCode, tap: CGEventTapLocation, count: Int) {
        for _ in 0..<count {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)?.post(tap: tap)
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)?.post(tap: tap)
        }
    }

    private func logWindows(_ label: String) {
        let me = ProcessInfo.processInfo.processIdentifier
        let list = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? []
        let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == me }
        let lockOwners = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "loginwindow" }
        SpikeLog.write("windows @ \(label): ours=\(mine.map { "layer \($0[kCGWindowLayer as String] ?? "?") onscreen \($0[kCGWindowIsOnscreen as String] ?? "?")" }) loginwindow=\(lockOwners.map { "layer \($0[kCGWindowLayer as String] ?? "?")" })")
    }
}

/// Captures frames, counts them and runs Vision face detection on a few. Reports once a second.
final class CameraProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "islet.spike.camera")
    private let lock = NSLock()
    private var frames = 0, faces = 0, started = Date(), firstFrame: Date?
    private var reporter: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    func start() {
        started = Date()
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else {
            SpikeLog.write("Q11: no camera device/input (authorization=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue))")
            return
        }
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { n in
                SpikeLog.write("Q11: camera session event \(n.name.rawValue) \(n.userInfo ?? [:])")
            })
        }
        queue.async { [session] in session.startRunning(); SpikeLog.write("Q11: startRunning returned, isRunning=\(session.isRunning)") }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            lock.lock(); let f = frames, fc = faces, first = firstFrame; lock.unlock()
            SpikeLog.write("Q11/Q14: t+\(Int(Date().timeIntervalSince(started)))s frames=\(f) frameWithFace=\(fc) firstFrameAfter=\(first.map { String(format: "%.2fs", $0.timeIntervalSince(started)) } ?? "none") running=\(session.isRunning)")
        }
        t.resume()
        reporter = t
    }

    func stop() {
        reporter?.cancel(); reporter = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        let s = session
        queue.async { s.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        frames += 1
        if firstFrame == nil { firstFrame = Date() }
        let n = frames
        lock.unlock()
        guard n % 10 == 0, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let req = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pb).perform([req])
        if let r = req.results, !r.isEmpty { lock.lock(); faces += 1; lock.unlock() }
    }
}

/// Private SkyLight route: put the window in its own space with an absurdly high level, which is how
/// lock-screen overlay tools get above loginwindow. Private API: personal use only, may break per macOS.
enum SkyLightProbe {
    @MainActor static func raise(window: Int) {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
            SpikeLog.write("Q13: SkyLight dlopen failed"); return
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(h, name).map { unsafeBitCast($0, to: type) }
        }
        typealias MainConn = @convention(c) () -> Int32
        typealias Create = @convention(c) (Int32, Int32, CFDictionary?) -> Int32
        typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
        typealias Show = @convention(c) (Int32, CFArray) -> Void
        typealias AddWin = @convention(c) (Int32, Int32, CFArray, Int32) -> Void
        guard let conn = sym("SLSMainConnectionID", MainConn.self), let create = sym("SLSSpaceCreate", Create.self),
              let setLevel = sym("SLSSpaceSetAbsoluteLevel", SetLevel.self), let show = sym("SLSShowSpaces", Show.self),
              let add = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWin.self) else {
            SpikeLog.write("Q13: SkyLight symbols missing"); return
        }
        let cid = conn()
        let space = create(cid, 1, nil)
        let r = setLevel(cid, space, 2_147_483_647)
        show(cid, [space] as CFArray)
        add(cid, space, [window] as CFArray, 7)
        SpikeLog.write("Q13: SkyLight space=\(space) setLevel=\(r) window=\(window). Is the scan shape visible now?")
    }
}

enum SpikeLog {
    private static let lock = NSLock()
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-M2-spike.log")
    static func write(_ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        lock.lock(); defer { lock.unlock() }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
}
#endif
