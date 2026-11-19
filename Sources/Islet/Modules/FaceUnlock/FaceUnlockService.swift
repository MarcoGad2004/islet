import AppKit
import Carbon.HIToolbox
import os

/// What the lock-screen scan is doing, for the island to draw.
@MainActor @Observable
final class ScanModel {
    enum Phase: Equatable { case looking, match, noMatch, failed(String) }
    var phase = Phase.looking
    var faceVisible = false
    /// Bumped on each "not recognized" so the grid shakes.
    var shakes = 0

    var label: String {
        switch phase {
        case .looking: return faceVisible ? "Checking" : "Looking for you"
        case .match: return "Welcome back"
        case .noMatch: return "Not recognized"
        case .failed(let message): return message
        }
    }
}

/// Face unlock itself: when the Mac locks and the screen is on, look for the enrolled face, and on a match
/// type the stored login password into the lock screen. Only ever acts on the lock screen.
@MainActor @Observable
final class FaceUnlockService {
    private static let enabledKey = "faceUnlockEnabled"
    private static let rejectedKey = "faceUnlockPasswordRejected"
    private static let maxAttempts = 3
    private static let log = Logger(subsystem: "com.marcogad.islet", category: "unlock")

    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); if !enabled { stop(collapseAfter: 0) } } }
    /// The stored password was typed and the Mac stayed locked: stop typing it until it is re-entered.
    private(set) var passwordRejected: Bool
    private(set) var accessibilityTrusted = AXIsProcessTrusted()

    private unowned let owner: FaceUnlockCoordinator
    private let island: IslandStore
    private var locked = false
    private var screenAwake = true
    private var attempts = 0
    private var stoppedForThisLock = false
    private var simulated = false
    private var camera: FaceCamera?
    private var engine: ScanEngine?
    private var model: ScanModel?
    private var timeout: Task<Void, Never>?
    private var unlockWaiter: CheckedContinuation<Bool, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(owner: FaceUnlockCoordinator, island: IslandStore) {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        passwordRejected = UserDefaults.standard.bool(forKey: Self.rejectedKey)
        self.owner = owner
        self.island = island
    }

    // MARK: Events

    func start() {
        locked = Self.sessionIsLocked()
        let dnc = DistributedNotificationCenter.default(), ws = NSWorkspace.shared.notificationCenter
        func add(_ c: NotificationCenter, _ name: String, _ h: @escaping @MainActor (FaceUnlockService) -> Void) {
            observers.append((c, c.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { h(self) } }
            }))
        }
        add(dnc, "com.apple.screenIsLocked") { $0.didLock() }
        add(dnc, "com.apple.screenIsUnlocked") { $0.didUnlock() }
        add(ws, NSWorkspace.screensDidWakeNotification.rawValue) { $0.screenAwake = true; $0.beginIfPossible() }
        add(ws, NSWorkspace.screensDidSleepNotification.rawValue) { $0.screenAwake = false; $0.stop(collapseAfter: 0) }
    }

    func refreshPermission() { accessibilityTrusted = AXIsProcessTrusted() }

    func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refreshPermission()
    }

    func clearPasswordRejected() { passwordRejected = false; UserDefaults.standard.set(false, forKey: Self.rejectedKey) }

    private func didLock() {
        Self.log.info("locked")
        locked = true
        attempts = 0
        stoppedForThisLock = false
        beginIfPossible()
    }

    private func didUnlock() {
        Self.log.info("unlocked")
        locked = false
        unlockWaiter?.resume(returning: true); unlockWaiter = nil
        // Let a "Welcome back" check finish before folding away.
        stop(collapseAfter: model?.phase == .match ? 0.9 : 0)
    }

    private static func sessionIsLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    // MARK: Scanning

    private func beginIfPossible() {
        refreshPermission()
        guard enabled, locked, screenAwake, !stoppedForThisLock, model == nil,
              owner.faces.isReady, owner.modelAvailable, accessibilityTrusted, !passwordRejected else {
            Self.log.info("not scanning: enabled=\(self.enabled) locked=\(self.locked) awake=\(self.screenAwake) ready=\(self.owner.faces.isReady) ax=\(self.accessibilityTrusted) rejected=\(self.passwordRejected)")
            return
        }
        scan(simulated: false)
    }

    /// Debug: run the whole scan on the unlocked desktop, without typing anything.
    func simulate() { stop(collapseAfter: 0); scan(simulated: true) }

    private func scan(simulated: Bool) {
        guard let embedder = owner.embedder, owner.faces.isEnrolled else { return }
        Task {
            guard await FaceCamera.requestAccess() else { Self.log.error("camera denied"); return }
            self.simulated = simulated
            let model = ScanModel()
            self.model = model
            island.scan = model
            island.setBase(.scan)

            let engine = ScanEngine(embedder: embedder, enrolled: owner.faces.embeddings, threshold: owner.faces.threshold) { event in
                Task { @MainActor [weak self] in self?.handle(event) }
            }
            self.engine = engine
            let analyzer = owner.analyzer
            let camera = FaceCamera()
            do {
                try camera.start { pb in
                    engine.handle(analyzer.analyze(pb))
                }
            } catch { Self.log.error("camera failed"); stop(collapseAfter: 0); return }
            self.camera = camera
            Self.log.info("scan started simulated=\(simulated)")
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.stoppedForThisLock = true
                self?.stop(collapseAfter: 0)
            }
        }
    }

    private func handle(_ event: ScanEngine.Event) {
        guard let model, model.phase == .looking else { return }
        switch event {
        case .face(let visible):
            model.faceVisible = visible
        case .match(let score):
            Self.log.info("match score=\(score)")
            model.phase = .match
            camera?.stop(); camera = nil
            Task { await completeMatch() }
        case .noMatch(let score):
            attempts += 1
            Self.log.info("no match best=\(score) attempt=\(self.attempts)")
            model.phase = .noMatch
            model.shakes += 1
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                guard self.model === model else { return }
                if attempts >= Self.maxAttempts {
                    stoppedForThisLock = true
                    stop(collapseAfter: 0)
                } else {
                    model.phase = .looking
                    engine?.resume()
                }
            }
        }
    }

    private func completeMatch() async {
        guard let model, model.phase == .match else { return }
        if simulated {
            // No typing in a simulated run: just let the check animation play before folding away.
            try? await Task.sleep(for: .milliseconds(900))
            stop(collapseAfter: 0); return
        }
        // Real unlock: type straight away. The check animation plays while the password goes in, and the
        // island folds up 0.9 s after the unlock (see didUnlock).

        guard locked, Self.sessionIsLocked(), let password = owner.faces.password() else {
            stop(collapseAfter: 0); return
        }
        Self.type(password)
        Self.log.info("typed password, waiting for unlock")
        let unlocked = await waitForUnlock(seconds: 3.5)
        if !unlocked {
            // Typed but still locked: the stored password is wrong. Don't keep trying and risk a lockout.
            Self.log.error("still locked after typing")
            passwordRejected = true
            UserDefaults.standard.set(true, forKey: Self.rejectedKey)
            model.phase = .failed("Password not accepted")
            stoppedForThisLock = true
            stop(collapseAfter: 2.5)
        }
    }

    private func waitForUnlock(seconds: Double) async -> Bool {
        if !locked { return true }
        return await withCheckedContinuation { cont in
            unlockWaiter = cont
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if let w = self?.unlockWaiter { self?.unlockWaiter = nil; w.resume(returning: false) }
            }
        }
    }

    private func stop(collapseAfter delay: Double) {
        timeout?.cancel(); timeout = nil
        camera?.stop(); camera = nil
        engine?.pause(); engine = nil
        let finished = model
        guard finished != nil else { return }
        let collapse = { [weak self] in
            guard let self, self.model === finished else { return }
            self.model = nil
            self.island.setBase(nil)
        }
        if delay <= 0 { collapse() } else { Task { try? await Task.sleep(for: .seconds(delay)); collapse() } }
    }

    // MARK: Typing

    /// Types the password as keystrokes into whatever has focus (the lock screen's password field), then Return.
    private static func type(_ password: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for unit in password.utf16 {
            var u = unit
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
                e?.post(tap: .cghidEventTap)
            }
            usleep(8_000)
        }
        usleep(60_000)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: down)?.post(tap: .cghidEventTap)
        }
    }
}
