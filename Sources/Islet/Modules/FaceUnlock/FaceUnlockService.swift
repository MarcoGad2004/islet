import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import os

/// What the lock-screen scan is doing, for the island to draw.
@MainActor @Observable
final class ScanModel {
    enum Phase: Equatable { case looking, match, noMatch, failed(String) }
    /// What it's doing while `.looking` with a face in view (owner, 2026-11-24: say it rather than "Checking").
    enum Step: Equatable { case recognizing, verifying, glow }
    var phase = Phase.looking
    var step = Step.recognizing
    var faceVisible = false
    /// The challenge is asked because the light is too bright for the quiet checks.
    var brightLight = false
    /// The face matches; it only needs to do this (blink, smile, turn) to show it is live.
    var challenge: LivenessChallenge?
    /// Bumped on each "not recognized" so the grid shakes.
    var shakes = 0
    /// When the face matched: the lock starts opening shortly after, and the check flies left at `flown`.
    var matchedAt: Date?
    var flown = false

    var label: String {
        switch phase {
        case .looking:
            if let challenge {
                return brightLight ? "Bright environment detected, \(challenge.prompt.prefix(1).lowercased() + challenge.prompt.dropFirst())" : challenge.prompt
            }
            guard faceVisible else { return "Looking for you" }
            switch step {
            case .recognizing: return "Recognizing you"
            case .verifying: return "Making sure it's you"
            case .glow: return "Hold still: checking with light"
            }
        case .match: return "Welcome back"
        case .noMatch: return "Not recognized"
        case .failed(let message): return message
        }
    }
}

/// Face unlock itself: look for the enrolled face on the lock screen, and on a match type the stored login password.
/// Only ever acts on the lock screen.
///
/// When it scans (DESIGN.md "Face scan"):
/// - The display wakes on a locked Mac (lid opened, display woken after it slept, screen saver dismissed): scan at once.
/// - The Mac locks while the display is on (power button, Ctrl-Cmd-Q, Apple menu): don't scan, so it doesn't unlock
///   straight back. The island shows the Command+Shift hint and the scan waits for those keys. Once the display
///   sleeps, the next wake scans at once again.
/// - After a scan gives up (no face in view, 3 misses, the time limit): wait for Command+Shift, until the display sleeps.
@MainActor @Observable
final class FaceUnlockService {
    private static let enabledKey = "faceUnlockEnabled"
    private static let rejectedKey = "faceUnlockPasswordRejected"
    private static let maxAttempts = 3
    /// Match -> check flies at 0.65 s (the shape folds into the wide bar) -> hold ~2 s -> disappear.
    private static let sequenceLength = 0.65 + 0.5 + 2.0
    private static let log = Logger(subsystem: "com.marcogad.islet", category: "unlock")
    /// Mean camera brightness below this (a few samples in a row) counts as a dark room.
    private static let darkLuma = 0.25
    /// No face in front of the camera for this long: say so and stop.
    private static let noFaceSeconds = 10.0

    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); if !enabled { stop(collapseAfter: 0) }; syncLockScreen() } }
    /// The stored password was typed and the Mac stayed locked: stop typing it until it is re-entered.
    private(set) var passwordRejected: Bool
    private(set) var accessibilityTrusted = AXIsProcessTrusted()

    private unowned let owner: FaceUnlockCoordinator
    private let island: IslandStore
    private var locked = false
    private var screenAwake = true
    /// Held from the scan's start to its end, so the display doesn't go to sleep from inactivity half way through
    /// (the lock screen's timer is short after the power button locked the Mac). 0 when not held.
    private var displayAssertion: IOPMAssertionID = 0
    private var attempts = 0
    /// Don't scan until Command+Shift is pressed (the Mac locked with the display on, or a scan gave up).
    /// Cleared when the display sleeps, so the next wake scans by itself.
    private var needsKey = false
    private var screensaverRunning = false
    private var noFaceTimer: Task<Void, Never>?
    private var simulated = false
    private var camera: FaceCamera?
    private var engine: ScanEngine?
    private var model: ScanModel?
    private var timeout: Task<Void, Never>?
    private var unlockWaiter: CheckedContinuation<Bool, Never>?
    /// The live matching sample, learned once the Mac actually unlocks.
    private var pendingLearn: [Float]?
    /// The match's typical score and pulse pattern, recorded once the Mac actually unlocks.
    private var pendingScore: Float?
    private var pendingPulse: [Double]?
    /// The last weak miss: if the password unlocks the Mac soon after, it was you.
    private var lastMiss: (score: Float, at: Date)?
    private var darkSamples = 0
    private var brightened = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var keyMonitor: Any?

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
        add(ws, NSWorkspace.screensDidWakeNotification.rawValue) { $0.screenAwake = true; $0.syncLockScreen(); $0.beginIfPossible() }
        add(ws, NSWorkspace.screensDidSleepNotification.rawValue) {
            $0.screenAwake = false; $0.needsKey = false; $0.syncLockScreen(); $0.stop(collapseAfter: 0)
        }
        add(dnc, "com.apple.screensaver.didstart") { $0.screensaverRunning = true; $0.stop(collapseAfter: 0) }
        add(dnc, "com.apple.screensaver.didstop") { $0.screensaverRunning = false; $0.needsKey = false; $0.beginIfPossible() }
        // Command+Shift on the lock screen starts a scan. Modifier changes reach a global monitor while locked
        // (RESEARCH.md Q24); it needs Accessibility, which typing the password needs anyway.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == [.command, .shift] else { return }
            MainActor.assumeIsolated { self?.keysPressed() }
        }
        syncLockScreen()
    }

    /// The island shows the closed padlock whenever the Mac is locked and the screen is on, plus the
    /// Command+Shift hint while a scan is waiting for those keys.
    private func syncLockScreen() {
        island.setLockScreen(locked && screenAwake)
        island.setLockHint(locked && screenAwake && needsKey && !screensaverRunning && model == nil && canScan)
    }

    /// Everything face unlock needs, apart from the lock state.
    private var canScan: Bool {
        enabled && owner.faces.isReady && owner.modelAvailable && accessibilityTrusted && !passwordRejected
    }

    private func keysPressed() {
        guard locked, screenAwake, !screensaverRunning, model == nil else { return }
        Self.log.info("command+shift: scanning")
        needsKey = false
        attempts = 0
        beginIfPossible()
    }

    func refreshPermission() { accessibilityTrusted = AXIsProcessTrusted() }

    func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refreshPermission()
    }

    func clearPasswordRejected() { passwordRejected = false; UserDefaults.standard.set(false, forKey: Self.rejectedKey); syncLockScreen() }

    private func didLock() {
        Self.log.info("locked")
        locked = true
        syncLockScreen()
        attempts = 0
        // Locked in front of you (power button, Ctrl-Cmd-Q): wait for Command+Shift. Locked as the display went to
        // sleep (lid closed, idle): the wake scans. The lock arrives after the display sleeps on lid close (Q26).
        needsKey = screenAwake && !screensaverRunning
        Self.log.info("needsKey=\(self.needsKey)")
        syncLockScreen()
        beginIfPossible()
    }

    private func didUnlock() {
        Self.log.info("unlocked")
        locked = false
        needsKey = false
        syncLockScreen()
        unlockWaiter?.resume(returning: true); unlockWaiter = nil
        if model?.matchedAt != nil, !simulated {
            // The password went in and the Mac opened: the live sample really was the owner.
            if let sample = pendingLearn {
                let kept = owner.faces.learn(sample)
                Self.log.info("learned=\(kept) looks=\(self.owner.faces.learned.count)")
            }
            if let score = pendingScore { owner.faces.recordGenuine(score) }
            if let profile = pendingPulse { owner.faces.learnPulse(profile) }
        } else if model?.matchedAt == nil, let miss = lastMiss, Date().timeIntervalSince(miss.at) < 60 {
            // Not recognized, then unlocked by hand within a minute: that face was most likely you.
            owner.faces.recordGenuine(miss.score)
            Self.log.info("miss then unlock: recorded \(miss.score)")
        }
        pendingLearn = nil; pendingScore = nil; pendingPulse = nil; lastMiss = nil
        if let model, let matched = model.matchedAt {
            // Face unlock: the scan sequence is the unlock animation. Let it finish (1.8 s from the match).
            stop(collapseAfter: max(0, matched.addingTimeInterval(Self.sequenceLength).timeIntervalSinceNow))
        } else {
            // Touch ID, Apple Watch or password: the lock-opens animation in the wings.
            stop(collapseAfter: 0)
            island.playUnlock()
        }
    }

    private static func sessionIsLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    // MARK: Scanning

    private func beginIfPossible() {
        refreshPermission()
        guard locked, screenAwake, !needsKey, !screensaverRunning, model == nil, canScan else {
            Self.log.info("not scanning: enabled=\(self.enabled) locked=\(self.locked) awake=\(self.screenAwake) needsKey=\(self.needsKey) saver=\(self.screensaverRunning) ready=\(self.owner.faces.isReady) ax=\(self.accessibilityTrusted) rejected=\(self.passwordRejected)")
            syncLockScreen()
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
            holdDisplayAwake()
            let model = ScanModel()
            self.model = model
            island.scan = model
            syncLockScreen()
            island.setBase(.scan)

            let faces = owner.faces
            // Too bright for the glow: say so up front, so a match goes straight to the blink.
            // The sensor often has no reading for its first few milliseconds (it showed -1 in bright rooms, so the scan
            // went on to wait for the spoof model and start a glow before finding out the room was too bright).
            let lux = await AmbientLight.settledLux()
            let bright = (lux ?? 0) > FacePulse.glowMaxLux
            Self.log.notice("scan lux=\(lux ?? -1) bright=\(bright)")
            let engine = ScanEngine(embedder: embedder, antiSpoof: owner.antiSpoof,
                                    enrolled: faces.allEmbeddings, threshold: faces.effectiveThreshold,
                                    security: faces.security, brightRoom: bright) { event in
                Task { @MainActor [weak self] in self?.handle(event) }
            }
            self.engine = engine
            pendingLearn = nil; pendingScore = nil; pendingPulse = nil
            darkSamples = 0
            let analyzer = owner.analyzer
            let camera = FaceCamera()
            let lightCounter = FrameCounter(every: 6)
            do {
                try camera.start { pb in
                    engine.handle(analyzer.analyze(pb), light: lightCounter.shouldProcess() ? FrameLight.luma(pb) : nil)
                }
            } catch { Self.log.error("camera failed"); stop(collapseAfter: 0); return }
            self.camera = camera
            // The glow may be needed, and it takes ~1.3 s to reach full strength: start it now, unseen.
            if faces.security.usesGlow && !bright { FaceGlow.shared.warm() }
            Self.log.info("scan started simulated=\(simulated)")
            startNoFaceTimer()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.giveUp(collapseAfter: 0)
            }
        }
    }

    /// No face for `noFaceSeconds`: "No face in view", then back to the Command+Shift hint.
    private func startNoFaceTimer() {
        noFaceTimer?.cancel()
        noFaceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.noFaceSeconds))
            guard !Task.isCancelled, let self, let model = self.model, model.phase == .looking, !self.simulated else { return }
            Self.log.info("no face in view")
            model.phase = .failed("No face in view")
            self.giveUp(collapseAfter: 1.6)
        }
    }

    /// The scan stopped without a match: wait for Command+Shift (or the next wake) before scanning again.
    private func giveUp(collapseAfter delay: Double) {
        needsKey = true
        stop(collapseAfter: delay)
    }

    private func handle(_ event: ScanEngine.Event) {
        if case .face(let visible) = event, model?.matchedAt == nil {
            if visible { noFaceTimer?.cancel(); noFaceTimer = nil } else { startNoFaceTimer() }
        }
        guard let model, model.phase == .looking else { return }
        switch event {
        case .face(let visible):
            model.faceVisible = visible
        case .challenge(let c, let bright):
            model.challenge = c
            model.brightLight = bright
        case .verifying:
            model.step = .verifying
        case .light(let luma):
            brightenIfDark(luma)
        case .pulse:
            model.step = .glow
            Task { await runPulse() }
        case .pulseResult(let verdict):
            let r = verdict.reading
            Self.log.notice("pulse passed=\(verdict.passed) \(verdict.reason ?? "", privacy: .public) contrast=\(r?.contrast ?? -1) shape=\(r?.shape ?? -1) relative=\(r?.relative ?? -1) agreement=\(r?.agreement ?? -1) matched=\(r?.matched ?? -1)")
        case .pulseSkipped(let why):
            Self.log.notice("pulse skipped: \(why, privacy: .public)")
        case .match(let score, let embedding, let via, let typical, let pulse):
            Self.log.notice("match score=\(score) typical=\(typical) via=\(via, privacy: .public)")
            model.challenge = nil
            // Every match showed it's live one way or another, so it's safe to learn from once the Mac opens.
            pendingLearn = embedding
            pendingScore = typical
            pendingPulse = pulse?.profile
            model.phase = .match
            model.matchedAt = Date()
            camera?.stop(); camera = nil
            // The dots become a check (0.5 s), then the check flies to the left wing as the padlock opens.
            Task { try? await Task.sleep(for: .milliseconds(650)); if self.model === model { model.flown = true; self.island.presentationChanged() } }
            Task { await completeMatch() }
        case .noMatch(let score, let refused):
            attempts += 1
            Self.log.notice("no match best=\(score) refused=\(refused) attempt=\(self.attempts)")
            if !refused, score > 0 { lastMiss = (score, Date()) }
            model.phase = .noMatch
            model.shakes += 1
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                guard self.model === model else { return }
                if attempts >= Self.maxAttempts {
                    giveUp(collapseAfter: 0)
                } else {
                    model.phase = .looking
                    model.step = .recognizing
                    model.challenge = nil; model.brightLight = false
                    engine?.resume()
                }
            }
        }
    }

    /// Automatic mode's depth check: hold the camera's exposure, wait a random moment, light the face in a known
    /// pattern (the glow, or one brightness swell where it can't be drawn), then let the engine judge the frames. A
    /// room the light sensor says is too bright skips it for a challenge.
    private func runPulse() async {
        guard let engine, let camera else { return }
        let lux = AmbientLight.lux()
        guard let share = FacePulse.glowShare(lux: lux) else {
            engine.skipPulse("bright room \(Int(lux ?? 0)) lux")
            return
        }
        let held = camera.holdExposure(true)
        try? await Task.sleep(for: .seconds(Double.random(in: FacePulse.lead)))
        // Gone, or already moved on to a challenge (the sun came out): leave the screen alone.
        guard self.engine === engine, engine.isPulsing else { camera.holdExposure(false); return }
        let learned = owner.faces.pulseProfiles
        let started: (FacePulse.Schedule) -> Void = { engine.pulseStarted($0, exposureHeld: held, learned: learned) }
        Self.log.notice("pulse lux=\(lux ?? -1) share=\(share)")
        let glow = FaceGlow.shared
        var schedule = glow.isAvailable ? await glow.play(share: share, onStart: started) : nil
        if schedule == nil, self.engine === engine, engine.isPulsing {
            schedule = await island.levels?.pulseForFaceScan(onStart: started)
        }
        try? await Task.sleep(for: .milliseconds(100))
        camera.holdExposure(false)
        engine.finishPulse(schedule, exposureHeld: held, learned: learned)
    }

    /// A dark room: ease the screen up so it lights the face, once per scan. `stop` eases it back.
    private func brightenIfDark(_ luma: Double) {
        guard !brightened else { return }
        darkSamples = luma < Self.darkLuma ? darkSamples + 1 : 0
        guard darkSamples >= 3 else { return }
        Self.log.info("dark room luma=\(luma), brightening")
        brightened = true
        island.levels?.boostForFaceScan()
    }

    private func completeMatch() async {
        guard let model, model.phase == .match else { return }
        if simulated {
            // No typing in a simulated run: let the whole sequence play, then fold away.
            try? await Task.sleep(for: .seconds(Self.sequenceLength))
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
            giveUp(collapseAfter: 2.5)
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

    private func holdDisplayAwake() {
        guard displayAssertion == 0 else { return }
        IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Dynamic Peninsula face unlock scan" as CFString, &displayAssertion)
    }

    private func releaseDisplay() {
        guard displayAssertion != 0 else { return }
        IOPMAssertionRelease(displayAssertion)
        displayAssertion = 0
    }

    private func stop(collapseAfter delay: Double) {
        releaseDisplay()
        timeout?.cancel(); timeout = nil
        noFaceTimer?.cancel(); noFaceTimer = nil
        camera?.stop(); camera = nil
        engine?.pause(); engine = nil
        FaceGlow.shared.cool()
        if brightened { brightened = false; island.levels?.endFaceScanBoost() }
        darkSamples = 0
        let finished = model
        guard finished != nil else { return }
        let collapse = { [weak self] in
            guard let self, self.model === finished else { return }
            self.model = nil
            self.island.setBase(nil)
            self.syncLockScreen()
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
