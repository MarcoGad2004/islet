import Foundation

/// Compares live frames with the enrolled face. Two good frames in a row is a match, once the face has shown it is
/// live (a blink, a smile or a head turn, when required) and isn't framed by a photo or screen edge. About half a
/// second of a visible face that doesn't match is a "not recognized" verdict, and so is a face that stays framed.
/// Once the face matches and the challenge is shown, it has `challengeSeconds` to do it (looking away to turn
/// doesn't count as a miss). Runs on the camera queue.
final class ScanEngine: @unchecked Sendable {
    enum Event: Sendable {
        case face(Bool)
        /// The face matches and now has to do this to unlock; nil once it isn't waiting.
        case challenge(LivenessChallenge?)
        /// `live` is true when the challenge was done in this scan (the sample is then safe to learn from).
        case match(score: Float, embedding: [Float], live: Bool)
        case noMatch(score: Float)
        /// Mean frame brightness, a few times a second.
        case light(Double)
    }

    static let challengeSeconds = 8.0

    private let embedder: FaceEmbedder
    private let enrolled: [[Float]]
    private let threshold: Float
    private let liveness: LivenessMode
    private let onEvent: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var matches = 0, misses = 0, best: Float = 0
    private var paused = false
    private var lastFace: Bool?
    private var lastPrompt: LivenessChallenge?
    private var detector: ChallengeDetector
    /// When the challenge was shown in this attempt.
    private var promptedAt: Date?
    private var faceLost = 0
    /// Recent frames that showed the face inside a rectangle (true) or not.
    private var framedHistory: [Bool] = []

    init(embedder: FaceEmbedder, enrolled: [[Float]], threshold: Float, liveness: LivenessMode,
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.embedder = embedder
        self.enrolled = enrolled
        self.threshold = threshold
        self.liveness = liveness
        self.onEvent = onEvent
        detector = ChallengeDetector(Self.pick(liveness))
    }

    /// Blink mode always asks for a blink; random mode picks again for every attempt.
    private static func pick(_ mode: LivenessMode) -> LivenessChallenge {
        mode == .random ? LivenessChallenge.allCases.randomElement() ?? .blink : .blink
    }

    /// After a verdict the engine ignores frames until `resume()`.
    func resume() {
        lock.lock(); paused = false; matches = 0; misses = 0; best = 0; framedHistory = []
        detector = ChallengeDetector(Self.pick(liveness)); promptedAt = nil; lock.unlock()
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
            // A face gone for a moment (not one dropped frame) has to do the challenge again: no doing it, then
            // swapping in a photo.
            if faceLost >= 5 { detector.reset(); framedHistory = [] }
            report(face: false)
            return
        }
        faceLost = 0
        report(face: true)
        let required = liveness != .off
        // Random challenges only count once asked for, so a video can't have done it beforehand by chance.
        if !(liveness == .random && promptedAt == nil) {
            detector.add(openness: a.eyeOpenness, mouth: a.mouthWidth, yaw: a.proxyX)
        }
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
                if !required || detector.done {
                    paused = true
                    prompt(nil)
                    onEvent(.match(score: score, embedding: e, live: required && detector.done))
                    return
                }
                if promptedAt == nil { promptedAt = Date() }
                prompt(detector.challenge)
            }
        } else {
            matches = 0
            // While the challenge is up a turned or smiling face may not match; only the time limit ends it.
            if promptedAt == nil { misses += 1 }
        }
        if let at = promptedAt, Date().timeIntervalSince(at) > Self.challengeSeconds { misses = 8 }
        if misses >= 8 { paused = true; prompt(nil); onEvent(.noMatch(score: framed ? 0 : best)); best = 0 }
    }

    private func report(face: Bool) {
        guard lastFace != face else { return }
        lastFace = face
        onEvent(.face(face))
    }

    private func prompt(_ challenge: LivenessChallenge?) {
        guard lastPrompt != challenge else { return }
        lastPrompt = challenge
        onEvent(.challenge(challenge))
    }
}
