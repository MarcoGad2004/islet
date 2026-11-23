import Foundation

/// The enrolment as the UI sees it.
@MainActor @Observable
final class EnrolmentModel {
    enum Phase: Equatable { case scanning, success, failed(String) }
    var phase = Phase.scanning
    var snapshot = EnrolmentSnapshot()

    var label: String {
        switch phase {
        case .success: return "Face enrolled"
        case .failed(let message): return message
        case .scanning:
            if !snapshot.faceVisible { return "Looking for you" }
            if !snapshot.calibrated { return "Hold still" }
            return snapshot.progress < 0.5 ? "Slowly move your head in a circle" : "Keep going"
        }
    }
}

/// Owns face unlock's data and drives enrolment and test runs. The Settings window talks to this.
@MainActor @Observable
final class FaceUnlockCoordinator {
    let faces = FaceStore()
    private(set) var enrolment: EnrolmentModel?
    private(set) var testScore: Float?
    private(set) var testingFace = false
    /// Test recognition: the liveness challenges done since the test started.
    private(set) var testSeen: Set<LivenessChallenge> = []
    /// Test recognition: the face is inside a photo or screen edge right now.
    private(set) var testFramed = false
    /// Test recognition: mean camera brightness, 0...1.
    private(set) var testLight: Double?
    /// Test recognition: the spoof model's recent mean, 0 (fake) ... 1 (real).
    private(set) var testLive: Float?
    /// Test recognition: the last light check, and whether one is running.
    private(set) var testPulse: FacePulse.Verdict?
    private(set) var testPulsing = false
    /// Test recognition: how the face is lit (harsh = direct sun, the challenge is asked at once).
    private(set) var testLighting: FacePulse.Lighting?
    /// The light sensor's reading when Check Light last ran.
    private(set) var testLux: Double?
    private(set) var modelAvailable = false

    private let island: IslandStore
    let embedder = FaceEmbedder()
    /// The spoof model; nil if it isn't in the bundle (face unlock still works, with the other checks).
    let antiSpoof = AntiSpoofModel()
    @ObservationIgnored private var testRecorder: PulseRecorder?
    private var camera: FaceCamera?
    private var timeout: Task<Void, Never>?
    let analyzer = FaceAnalyzer()
    @ObservationIgnored private(set) lazy var unlock = FaceUnlockService(owner: self, island: island)

    init(island: IslandStore) {
        self.island = island
        modelAvailable = embedder != nil
    }

    var isEnrolling: Bool { enrolment?.phase == .scanning }

    // MARK: Enrolment

    /// Returns an error message, or nil when the scan started.
    func beginEnrolment() async -> String? {
        guard let embedder else { return "The face model is missing. Run scripts/fetch-model.sh, then xcodegen generate." }
        guard await FaceCamera.requestAccess() else { return "Camera access is off. Allow it in System Settings → Privacy & Security → Camera." }
        stopCamera()

        let model = EnrolmentModel()
        enrolment = model
        island.enrolment = model
        island.setBase(.enrol)

        let engine = EnrolmentEngine(embedder: embedder, onUpdate: { snap in
            Task { @MainActor in model.snapshot = snap }
        }, onFinish: { [weak self] samples in
            Task { @MainActor in self?.finishEnrolment(samples, model: model) }
        })
        let analyzer = self.analyzer
        let camera = FaceCamera()
        let counter = FrameCounter(every: 2)
        do {
            try camera.start { pb in
                guard counter.shouldProcess() else { return }
                engine.handle(analyzer.analyze(pb))
            }
        } catch {
            island.setBase(nil)
            return Self.cameraMessage(error)
        }
        self.camera = camera
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            self?.fail(model, "That took too long. Try again")
        }
        return nil
    }

    func cancelEnrolment() {
        timeout?.cancel()
        stopCamera()
        island.setBase(nil)
        enrolment = nil
    }

    private func finishEnrolment(_ samples: [[Float]], model: EnrolmentModel) {
        timeout?.cancel()
        stopCamera()
        // A rough sanity check that the scan saw one consistent face.
        guard FaceMatcher.consistency(samples) >= 0.35, faces.saveEmbeddings(samples) else {
            fail(model, "Couldn't get a clear scan. Try better light")
            return
        }
        model.phase = .success
        Task { [island] in
            try? await Task.sleep(for: .seconds(2.4))
            island.setBase(nil)
        }
    }

    private func fail(_ model: EnrolmentModel, _ message: String) {
        stopCamera()
        model.phase = .failed(message)
        Task { [island] in
            try? await Task.sleep(for: .seconds(2.4))
            island.setBase(nil)
        }
    }

    // MARK: Test recognition

    func startTest() async -> String? {
        guard let embedder else { return "The face model is missing." }
        guard faces.isEnrolled else { return "Set up your face first." }
        guard await FaceCamera.requestAccess() else { return "Camera access is off." }
        stopCamera()
        testScore = nil
        testSeen = []; testFramed = false; testLight = nil; testLive = nil; testPulse = nil
        testingFace = true
        let enrolled = faces.allEmbeddings
        let threshold = faces.effectiveThreshold
        let analyzer = self.analyzer
        let antiSpoof = faces.spoofModel ? self.antiSpoof : nil
        // Every other frame: often enough to catch a blink (~100-150 ms). Every frame while the light check records.
        let counter = FrameCounter(every: 2)
        let liveness = TestLiveness()
        let spoof = TestSpoof()
        let recorder = PulseRecorder()
        testRecorder = recorder
        let camera = FaceCamera()
        do {
            try camera.start { [weak self] pb in
                let recording = recorder.isRecording
                guard counter.shouldProcess() || recording else { return }
                var score: Float?, framed = false
                let a = analyzer.analyze(pb)
                if let a, a.boxWidth > 0.14, let img = a.alignedImage(), let e = embedder.embed(img) {
                    score = FaceMatcher.score(e, enrolled: enrolled)
                    framed = a.framed
                    if recording {
                        let m = FacePulse.measure(pb, points: a.points, face: a.box)
                        recorder.add(FacePulse.Frame(time: FaceCamera.captured(pb), face: m.face, background: m.background,
                                                     matched: (score ?? 0) >= threshold, luma: FrameLight.luma(pb)))
                    }
                }
                let lighting = a.flatMap { FacePulse.lighting(pb, points: $0.points, face: $0.box) }
                let live = a.flatMap { a in antiSpoof?.live(pb, face: a.box) }.map { spoof.add($0) } ?? spoof.mean
                let seen = liveness.add(a)
                let light = FrameLight.luma(pb)
                Task { @MainActor in
                    guard let self, self.testingFace else { return }
                    self.testScore = score; self.testFramed = framed; self.testLight = light; self.testLive = live
                    self.testLighting = lighting
                    self.testSeen.formUnion(seen)
                }
            }
        } catch { testingFace = false; return Self.cameraMessage(error) }
        self.camera = camera
        return nil
    }

    func stopTest() {
        stopCamera()
        testingFace = false
        testScore = nil
        testSeen = []; testFramed = false; testLight = nil; testLive = nil; testPulse = nil; testPulsing = false
        testLighting = nil; testLux = nil
        testRecorder = nil
    }

    /// Test recognition: run the light pulse once, as a scan would, and show what it measured.
    func runTestPulse() async {
        guard testingFace, !testPulsing, let camera, let recorder = testRecorder else { return }
        testPulsing = true; testPulse = nil
        defer { testPulsing = false }
        let lux = AmbientLight.lux()
        testLux = lux
        guard let share = FacePulse.glowShare(lux: lux) else {
            testPulse = .inconclusive(String(format: "too bright (%.0f lux), a scan asks for a challenge", lux ?? 0), nil)
            return
        }
        let glow = FaceGlow.shared
        glow.warm()
        let held = camera.holdExposure(true)
        recorder.begin()
        try? await Task.sleep(for: .seconds(Double.random(in: FacePulse.lead)))
        var schedule = glow.isAvailable ? await glow.play(share: share) : nil
        if schedule == nil { schedule = await island.levels?.pulseForFaceScan() }
        glow.cool()
        try? await Task.sleep(for: .milliseconds(100))
        let frames = recorder.end()
        camera.holdExposure(false)
        guard testingFace else { return }
        testPulse = schedule.map { FacePulse.judge(frames, schedule: $0, exposureHeld: held, learned: faces.pulseProfiles) }
            ?? .inconclusive("the screen's light can't be set", nil)
        if let schedule { Self.record(frames, schedule: schedule, glow: glow.last, lux: lux, verdict: testPulse) }
    }

    /// Check Light's raw numbers, one row per frame, to see why it vouched or not:
    /// ~/Library/Application Support/Islet/light-check.csv (the latest run; numbers only, no images).
    private static func record(_ frames: [FacePulse.Frame], schedule: FacePulse.Schedule,
                               glow: (glow: FacePulse.Glow, start: Date)?, lux: Double?, verdict: FacePulse.Verdict?) {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Islet", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let origin = glow?.start ?? schedule.low.first?.lowerBound ?? Date()
        func n(_ v: Double?) -> String { v.map { String(format: "%.5f", $0) } ?? "" }
        var lines = [
            "# lux \(n(lux)) verdict \(verdict.map { "\($0)" } ?? "none")",
            "# glow \(glow.map { "low \(n($0.glow.low)) high \(n($0.glow.high)) steps \($0.glow.steps.map { $0 ? "H" : "L" }.joined())" } ?? "none (swell)")",
            "t,window,commanded,matched,luma," + FacePulse.Patch.allCases.map { "\($0)" }.joined(separator: ",") + ",bgMedian,bgReadable",
        ]
        for f in frames {
            let t = f.time.timeIntervalSince(origin)
            let window = schedule.inHigh(f.time) ? "H" : schedule.inLow(f.time) ? "L" : ""
            let commanded = glow.map { $0.glow.at(t) }.map { $0.value * $0.alpha }
            let bg = f.background.compactMap { $0 }
            lines.append([n(t), window, n(commanded), f.matched ? "1" : "0", n(f.luma)].joined(separator: ",") + ","
                         + f.face.map(n).joined(separator: ",") + ",\(n(FacePulse.median(bg))),\(bg.count)")
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("light-check.csv"), atomically: true, encoding: .utf8)
    }

    private static func cameraMessage(_ error: Error) -> String {
        if case FaceCamera.CameraError.noCamera = error {
            return "Face unlock only uses this Mac's built-in camera, and it isn't available (is the lid closed?)."
        }
        return "Couldn't start the camera."
    }

    private func stopCamera() { camera?.stop(); camera = nil }
}

/// One detector per liveness challenge, which the camera queue can share.
final class TestLiveness: @unchecked Sendable {
    private var detectors = LivenessChallenge.allCases.map(ChallengeDetector.init)
    private let lock = NSLock()
    func add(_ a: FaceAnalysis?) -> Set<LivenessChallenge> {
        lock.lock(); defer { lock.unlock() }
        if let a {
            for i in detectors.indices { detectors[i].add(openness: a.eyeOpenness, mouth: a.mouthWidth, yaw: a.proxyX) }
        }
        return Set(detectors.filter(\.done).map(\.challenge))
    }
}

/// The spoof model's recent frames in Test recognition, shared with the camera queue.
final class TestSpoof: @unchecked Sendable {
    private var tracker = SpoofTracker()
    private let lock = NSLock()
    func add(_ v: Float) -> Float? { lock.lock(); defer { lock.unlock() }; tracker.add(v); return tracker.mean }
    var mean: Float? { lock.lock(); defer { lock.unlock() }; return tracker.mean }
}

/// Lets every Nth camera frame through (cheap thread-safe counter).
final class FrameCounter: @unchecked Sendable {
    private let every: Int
    private var n = 0
    private let lock = NSLock()
    init(every: Int) { self.every = every }
    func shouldProcess() -> Bool {
        lock.lock(); defer { lock.unlock() }
        n += 1
        return n % every == 0
    }
}
