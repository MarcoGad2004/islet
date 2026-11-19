import Foundation

/// Compares live frames with the enrolled face. Two good frames in a row is a match; about half a second of
/// a visible face that doesn't match is a "not recognized" verdict. Runs on the camera queue.
final class ScanEngine: @unchecked Sendable {
    enum Event: Sendable {
        case face(Bool)
        case match(score: Float)
        case noMatch(score: Float)
    }

    private let embedder: FaceEmbedder
    private let enrolled: [[Float]]
    private let threshold: Float
    private let onEvent: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var matches = 0, misses = 0, best: Float = 0
    private var paused = false
    private var lastFace: Bool?

    init(embedder: FaceEmbedder, enrolled: [[Float]], threshold: Float, onEvent: @escaping @Sendable (Event) -> Void) {
        self.embedder = embedder
        self.enrolled = enrolled
        self.threshold = threshold
        self.onEvent = onEvent
    }

    /// After a verdict the engine ignores frames until `resume()`.
    func resume() { lock.lock(); paused = false; matches = 0; misses = 0; best = 0; lock.unlock() }
    func pause() { lock.lock(); paused = true; lock.unlock() }

    func handle(_ analysis: FaceAnalysis?) {
        lock.lock(); defer { lock.unlock() }
        guard !paused else { return }
        guard let a = analysis, a.boxWidth > 0.14, let image = a.alignedImage(), let e = embedder.embed(image) else {
            matches = 0; misses = 0
            report(face: false)
            return
        }
        report(face: true)
        let score = FaceMatcher.score(e, enrolled: enrolled)
        best = max(best, score)
        if score >= threshold {
            matches += 1; misses = 0
            if matches >= 2 { paused = true; onEvent(.match(score: score)) }
        } else {
            matches = 0; misses += 1
            if misses >= 8 { paused = true; onEvent(.noMatch(score: best)); best = 0 }
        }
    }

    private func report(face: Bool) {
        guard lastFace != face else { return }
        lastFace = face
        onEvent(.face(face))
    }
}
