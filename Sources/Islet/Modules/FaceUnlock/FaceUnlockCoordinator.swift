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
    /// Test recognition: a blink was seen since the test started.
    private(set) var testBlinked = false
    /// Test recognition: the face is inside a photo or screen edge right now.
    private(set) var testFramed = false
    /// Test recognition: mean camera brightness, 0...1.
    private(set) var testLight: Double?
    private(set) var modelAvailable = false

    private let island: IslandStore
    let embedder = FaceEmbedder()
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
            return "Couldn't start the camera."
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
        testBlinked = false; testFramed = false; testLight = nil
        testingFace = true
        let enrolled = faces.allEmbeddings
        let analyzer = self.analyzer
        // Every other frame: often enough to catch a blink (~100-150 ms).
        let counter = FrameCounter(every: 2)
        let blink = TestBlink()
        let camera = FaceCamera()
        do {
            try camera.start { [weak self] pb in
                guard counter.shouldProcess() else { return }
                var score: Float?, framed = false
                let a = analyzer.analyze(pb)
                if let a, a.boxWidth > 0.14, let img = a.alignedImage(), let e = embedder.embed(img) {
                    score = FaceMatcher.score(e, enrolled: enrolled)
                    framed = a.framed
                }
                let blinked = blink.add(a?.eyeOpenness)
                let light = FrameLight.luma(pb)
                Task { @MainActor in
                    guard let self, self.testingFace else { return }
                    self.testScore = score; self.testFramed = framed; self.testLight = light
                    if blinked { self.testBlinked = true }
                }
            }
        } catch { testingFace = false; return "Couldn't start the camera." }
        self.camera = camera
        return nil
    }

    func stopTest() {
        stopCamera()
        testingFace = false
        testScore = nil
        testBlinked = false; testFramed = false; testLight = nil
    }

    private func stopCamera() { camera?.stop(); camera = nil }
}

/// A blink detector the camera queue can share.
final class TestBlink: @unchecked Sendable {
    private var detector = BlinkDetector()
    private let lock = NSLock()
    func add(_ openness: Double?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let openness { detector.add(openness) }
        return detector.blinked
    }
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
