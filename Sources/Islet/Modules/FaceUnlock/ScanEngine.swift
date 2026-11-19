import Foundation

/// Compares live frames with the enrolled face. Two good frames in a row is a match, once the face has shown it is
/// live (a blink, when required) and isn't framed by a photo or screen edge. About half a second of a visible face
/// that doesn't match is a "not recognized" verdict, and so is a face that stays framed. Runs on the camera queue.
final class ScanEngine: @unchecked Sendable {
    enum Event: Sendable {
        case face(Bool)
        /// The face matches but hasn't blinked yet.
        case waitingForBlink(Bool)
        /// `live` is true when a blink was seen in this scan (the sample is then safe to learn from).
        case match(score: Float, embedding: [Float], live: Bool)
        case noMatch(score: Float)
        /// Mean frame brightness, a few times a second.
        case light(Double)
    }

    private let embedder: FaceEmbedder
    private let enrolled: [[Float]]
    private let threshold: Float
    private let requireBlink: Bool
    private let onEvent: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var matches = 0, misses = 0, best: Float = 0
    private var paused = false
    private var lastFace: Bool?
    private var lastWaiting = false
    private var blink = BlinkDetector()
    private var faceLost = 0
    /// Recent frames that showed the face inside a rectangle (true) or not.
    private var framedHistory: [Bool] = []

    init(embedder: FaceEmbedder, enrolled: [[Float]], threshold: Float, requireBlink: Bool,
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.embedder = embedder
        self.enrolled = enrolled
        self.threshold = threshold
        self.requireBlink = requireBlink
        self.onEvent = onEvent
    }

    /// After a verdict the engine ignores frames until `resume()`.
    func resume() {
        lock.lock(); paused = false; matches = 0; misses = 0; best = 0; framedHistory = []; blink.reset(); lock.unlock()
    }
    func pause() { lock.lock(); paused = true; lock.unlock() }

    /// `light` is the frame's mean brightness when it was measured for this frame.
    func handle(_ analysis: FaceAnalysis?, light: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let light { onEvent(.light(light)) }
        guard !paused else { return }
        guard let a = analysis, a.boxWidth > 0.14, let image = a.alignedImage(), let e = embedder.embed(image) else {
            matches = 0; misses = 0
            faceLost += 1
            // A face gone for a moment (not one dropped frame) has to blink again: no blinking, then swapping in a photo.
            if faceLost >= 5 { blink.reset(); framedHistory = [] }
            report(face: false)
            return
        }
        faceLost = 0
        report(face: true)
        blink.add(a.eyeOpenness)
        framedHistory.append(a.framed)
        if framedHistory.count > 10 { framedHistory.removeFirst() }
        let framed = framedHistory.filter { $0 }.count >= 4

        let score = FaceMatcher.score(e, enrolled: enrolled)
        best = max(best, score)
        if framed {
            // A photo or screen held up: never a match, and it counts towards "not recognized".
            matches = 0; misses += 1
        } else if score >= threshold {
            matches += 1; misses = 0
            if matches >= 2 {
                if !requireBlink || blink.blinked {
                    paused = true
                    reportWaiting(false)
                    onEvent(.match(score: score, embedding: e, live: blink.blinked))
                    return
                }
                reportWaiting(true)
            }
        } else {
            matches = 0; misses += 1
        }
        if misses >= 8 { paused = true; reportWaiting(false); onEvent(.noMatch(score: framed ? 0 : best)); best = 0 }
    }

    private func report(face: Bool) {
        guard lastFace != face else { return }
        lastFace = face
        onEvent(.face(face))
        if !face { reportWaiting(false) }
    }

    private func reportWaiting(_ waiting: Bool) {
        guard lastWaiting != waiting else { return }
        lastWaiting = waiting
        onEvent(.waitingForBlink(waiting))
    }
}
