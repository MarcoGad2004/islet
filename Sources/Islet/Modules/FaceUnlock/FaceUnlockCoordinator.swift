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
        testingFace = true
        let enrolled = faces.embeddings
        let analyzer = self.analyzer
        let counter = FrameCounter(every: 4)
        let camera = FaceCamera()
        do {
            try camera.start { [weak self] pb in
                guard counter.shouldProcess() else { return }
                var score: Float?
                if let a = analyzer.analyze(pb), a.boxWidth > 0.14, let img = a.alignedImage(), let e = embedder.embed(img) {
                    score = FaceMatcher.score(e, enrolled: enrolled)
                }
                Task { @MainActor in self?.testScore = score }
            }
        } catch { testingFace = false; return "Couldn't start the camera." }
        self.camera = camera
        return nil
    }

    func stopTest() {
        stopCamera()
        testingFace = false
        testScore = nil
    }

    private func stopCamera() { camera?.stop(); camera = nil }
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
