import Foundation

/// Compares live frames with the enrolled face. Two good frames in a row is a match, once the face has shown it is
/// live and isn't a photo or screen (a rectangle edge around it, or the spoof model sure it's fake). About half a
/// second of a visible face that doesn't match is a "not recognized" verdict, and so is a face that stays refused.
///
/// Showing it's live:
/// - Automatic: the screen-light pulse runs (the service drives the brightness, then calls `finishPulse`). When it
///   passes and the spoof model says live, that's the match, no action needed. Otherwise a random challenge.
/// - Random / Blink: the challenge. Once the face matches and it's shown, it has `challengeSeconds` to do it
///   (looking away to turn doesn't count as a miss).
/// Runs on the camera queue; `finishPulse` may come from any thread.
final class ScanEngine: @unchecked Sendable {
    enum Event: Sendable {
        case face(Bool)
        /// The face matches and now has to do this to unlock; nil once it isn't waiting.
        case challenge(LivenessChallenge?)
        /// The face matches: run the brightness pulse, then call `finishPulse`.
        case pulse
        case pulseResult(FacePulse.Verdict)
        /// `live` is true when the face proved it's live in this scan (the sample is then safe to learn from).
        /// `typical` is the median score of the face's frames in this attempt, for the adaptive threshold.
        case match(score: Float, embedding: [Float], live: Bool, typical: Float, pulse: FacePulse.Reading?)
        /// `refused` is true when it was a photo edge or the spoof model rather than a weak match.
        case noMatch(score: Float, refused: Bool)
        /// Mean frame brightness, a few times a second.
        case light(Double)
    }

    static let challengeSeconds = 8.0
    /// The pulse should end within this; if the service never answers, fall back to a challenge.
    static let pulseSeconds = 4.0

    private enum PulseState { case idle, running(since: Date, frames: [FacePulse.Frame]), done }

    private let embedder: FaceEmbedder
    private let antiSpoof: AntiSpoofModel?
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
    private var spoof = SpoofTracker()
    private var spoofFrame = 0
    private var pulse = PulseState.idle
    /// Automatic mode couldn't vouch passively: a challenge now, as in Random.
    private var fallback = false
    private var scores: [Float] = []
    private var lastMatch: (score: Float, embedding: [Float])?

    init(embedder: FaceEmbedder, antiSpoof: AntiSpoofModel?, enrolled: [[Float]], threshold: Float, liveness: LivenessMode,
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.embedder = embedder
        self.antiSpoof = antiSpoof
        self.enrolled = enrolled
        self.threshold = threshold
        self.liveness = liveness
        self.onEvent = onEvent
        detector = ChallengeDetector(Self.pick(liveness))
    }

    /// Blink mode always asks for a blink; the others pick again for every attempt.
    private static func pick(_ mode: LivenessMode) -> LivenessChallenge {
        mode == .blink ? .blink : LivenessChallenge.allCases.randomElement() ?? .blink
    }

    /// Random challenges, and Automatic's fallback, only count once they're shown.
    private var randomLike: Bool { liveness == .random || (liveness == .automatic && fallback) }

    /// After a verdict the engine ignores frames until `resume()`.
    func resume() {
        lock.lock(); defer { lock.unlock() }
        paused = false; matches = 0; misses = 0; best = 0; framedHistory = []
        detector = ChallengeDetector(Self.pick(liveness)); promptedAt = nil
        spoof.reset(); pulse = .idle; fallback = false; scores = []; lastMatch = nil
    }
    func pause() { lock.lock(); paused = true; lock.unlock() }

    /// `light` is the frame's mean brightness when it was measured for this frame.
    func handle(_ analysis: FaceAnalysis?, light: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let light { onEvent(.light(light)) }
        guard !paused else { return }
        let now = Date()
        guard let a = analysis, a.boxWidth > 0.14, let image = a.alignedImage(), let e = embedder.embed(image) else {
            matches = 0; misses = 0
            faceLost += 1
            // A face gone for a moment (not one dropped frame) has to prove it's live again: no doing it, then
            // swapping in a photo.
            if faceLost >= 5 {
                detector.reset(); framedHistory = []; spoof.reset()
                if case .running = pulse { finishPulseLocked(nil, exposureHeld: false, learned: []) }
            }
            report(face: false)
            return
        }
        faceLost = 0
        report(face: true)
        let required = liveness != .off
        if liveness == .blink || liveness == .off || (randomLike && promptedAt != nil) {
            detector.add(openness: a.eyeOpenness, mouth: a.mouthWidth, yaw: a.proxyX)
        }
        framedHistory.append(a.framed)
        if framedHistory.count > 10 { framedHistory.removeFirst() }
        let framed = framedHistory.filter { $0 }.count >= 4
        spoofFrame += 1
        if let antiSpoof, spoofFrame % 2 == 0, let live = antiSpoof.live(a.pixelBuffer, face: a.box) { spoof.add(live) }
        let refused = framed || spoof.verdict == .spoof

        let score = FaceMatcher.score(e, enrolled: enrolled)
        best = max(best, score)
        scores.append(score)
        if score >= threshold { lastMatch = (score, e) }
        if case .running(let since, var frames) = pulse {
            let m = FacePulse.measure(a.pixelBuffer, points: a.points, face: a.box)
            frames.append(FacePulse.Frame(time: now, face: m.face, background: m.background, matched: score >= threshold && !refused))
            pulse = .running(since: since, frames: frames)
            if now.timeIntervalSince(since) > Self.pulseSeconds { finishPulseLocked(nil, exposureHeld: false, learned: []); return }
        }
        let pulsing: Bool = { if case .running = pulse { return true }; return false }()

        if refused {
            // A photo or screen: never a match, and it counts towards "not recognized".
            matches = 0; misses += 1
        } else if score >= threshold {
            matches += 1; misses = 0
            if matches >= 2 {
                if !required || (liveness != .automatic || fallback) && detector.done {
                    finish(score: score, embedding: e, live: required, pulse: nil)
                    return
                }
                if liveness == .automatic && !fallback {
                    if case .idle = pulse { pulse = .running(since: now, frames: []); onEvent(.pulse) }
                } else {
                    if promptedAt == nil { promptedAt = now }
                    prompt(detector.challenge)
                }
            }
        } else {
            matches = 0
            // While the challenge or the pulse is on, a turned face or a changing light may not match; only the
            // time limits end it.
            if promptedAt == nil && !pulsing { misses += 1 }
        }
        if let at = promptedAt, now.timeIntervalSince(at) > Self.challengeSeconds { misses = 8 }
        if misses >= 8 {
            paused = true; prompt(nil)
            onEvent(.noMatch(score: refused ? 0 : best, refused: refused)); best = 0
        }
    }

    /// The service ran the brightness pulse (nil when it couldn't). Judges it, then unlocks or asks for a challenge.
    func finishPulse(_ schedule: FacePulse.Schedule?, exposureHeld: Bool, learned: [[Double]]) {
        lock.lock(); defer { lock.unlock() }
        guard !paused else { return }
        finishPulseLocked(schedule, exposureHeld: exposureHeld, learned: learned)
    }

    private func finishPulseLocked(_ schedule: FacePulse.Schedule?, exposureHeld: Bool, learned: [[Double]]) {
        guard case .running(_, let frames) = pulse else { return }
        pulse = .done
        let verdict = schedule.map { FacePulse.judge(frames, schedule: $0, exposureHeld: exposureHeld, learned: learned) }
            ?? .inconclusive("no pulse", nil)
        onEvent(.pulseResult(verdict))
        if case .passed(let reading) = verdict, spoof.verdict == .live, faceLost == 0, let m = lastMatch {
            finish(score: m.score, embedding: m.embedding, live: true, pulse: reading)
            return
        }
        // Couldn't vouch for it passively: ask for a random challenge, as in Random mode.
        fallback = true
        promptedAt = Date()
        prompt(detector.challenge)
    }

    private func finish(score: Float, embedding: [Float], live: Bool, pulse reading: FacePulse.Reading?) {
        paused = true
        prompt(nil)
        let typical = FaceMatcher.median(scores) ?? score
        onEvent(.match(score: score, embedding: embedding, live: live, typical: typical, pulse: reading))
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
