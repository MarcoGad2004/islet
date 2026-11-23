import Foundation

/// Compares live frames with the enrolled face. Two good frames in a row is a match, once the face has shown it is
/// live and isn't a photo or screen (a rectangle edge around it, or the spoof model sure it's fake). About half a
/// second of a visible face that doesn't match is a "not recognized" verdict, and so is a face that stays refused.
///
/// Showing it's live:
/// - Automatic: the screen-light pulse runs (the service drives the brightness, calls `pulseStarted` as the swell
///   begins and `finishPulse` once it's back). It's judged as soon as the swell peaks: when it passes and the spoof
///   model says live, that's the match, no action needed. Otherwise a random challenge. In harsh light (direct sun,
///   which drowns out the screen) the pulse is skipped and the challenge asked at once, and so it is for the rest of
///   the scan once a pulse got no response.
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
        /// Automatic went straight to a challenge without the pulse, and why.
        case pulseSkipped(String)
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
    /// Automatic's fallback challenge is always a blink.
    private let blinkFallback: Bool
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
    /// The running pulse's swell, once the service started it, and what to judge it with.
    private var pulseSchedule: FacePulse.Schedule?
    private var pulseHeld = false
    private var pulseLearned: [[Double]] = []
    /// Recent frames lit harshly (direct sun).
    private var harshHistory: [Bool] = []
    /// A pulse got no response in this scan: later attempts go straight to the challenge. Kept across `resume()`.
    private var skipPulse = false
    /// Peak frames needed to judge the pulse early.
    static let earlyPeakFrames = 4

    init(embedder: FaceEmbedder, antiSpoof: AntiSpoofModel?, enrolled: [[Float]], threshold: Float, liveness: LivenessMode,
         blinkFallback: Bool = false,
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.embedder = embedder
        self.antiSpoof = antiSpoof
        self.enrolled = enrolled
        self.threshold = threshold
        self.liveness = liveness
        self.blinkFallback = blinkFallback
        self.onEvent = onEvent
        detector = ChallengeDetector(Self.pick(liveness, blinkFallback: blinkFallback))
    }

    /// Blink mode always asks for a blink, and so does Automatic when its fallback is set to blink only; otherwise a
    /// new pick for every attempt.
    static func pick(_ mode: LivenessMode, blinkFallback: Bool) -> LivenessChallenge {
        mode == .blink || (mode == .automatic && blinkFallback) ? .blink : LivenessChallenge.allCases.randomElement() ?? .blink
    }

    /// Random challenges, and Automatic's fallback, only count once they're shown.
    private var randomLike: Bool { liveness == .random || (liveness == .automatic && fallback) }

    /// After a verdict the engine ignores frames until `resume()`.
    func resume() {
        lock.lock(); defer { lock.unlock() }
        paused = false; matches = 0; misses = 0; best = 0; framedHistory = []
        detector = ChallengeDetector(Self.pick(liveness, blinkFallback: blinkFallback)); promptedAt = nil
        spoof.reset(); pulse = .idle; fallback = false; scores = []; lastMatch = nil
        pulseSchedule = nil; harshHistory = []
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
        if let l = FacePulse.lighting(a.pixelBuffer, points: a.points, face: a.box) {
            harshHistory.append(l.harsh)
            if harshHistory.count > 6 { harshHistory.removeFirst() }
        }
        let harsh = harshHistory.count >= 3 && harshHistory.filter { $0 }.count * 2 > harshHistory.count
        // In harsh light the spoof model can't be trusted to refuse a real face; the challenge decides instead.
        let refused = framed || (spoof.verdict == .spoof && !harsh)

        let score = FaceMatcher.score(e, enrolled: enrolled)
        best = max(best, score)
        scores.append(score)
        if score >= threshold { lastMatch = (score, e) }
        if case .running = pulse, harsh, pulseSchedule == nil {
            // The sun came out before the swell started: don't bother with it.
            pulse = .done; fallback = true
            onEvent(.pulseSkipped("harsh light"))
        }
        if case .running(let since, var frames) = pulse {
            let m = FacePulse.measure(a.pixelBuffer, points: a.points, face: a.box)
            frames.append(FacePulse.Frame(time: now, face: m.face, background: m.background, matched: score >= threshold && !refused))
            pulse = .running(since: since, frames: frames)
            if now.timeIntervalSince(since) > Self.pulseSeconds { finishPulseLocked(nil, exposureHeld: false, learned: []); return }
            // Judge as soon as the swell has peaked for a few frames, rather than waiting for it to come back.
            if let schedule = pulseSchedule, frames.filter({ schedule.inPeak($0.time) }).count >= Self.earlyPeakFrames {
                finishPulseLocked(schedule, exposureHeld: pulseHeld, learned: pulseLearned)
                if paused { return }
            }
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
                if liveness == .automatic && !fallback, case .idle = pulse, harsh || skipPulse {
                    // Direct sun drowns out the screen's light: don't swell it, ask for the challenge now.
                    fallback = true
                    pulse = .done
                    onEvent(.pulseSkipped(harsh ? "harsh light" : "no response earlier"))
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

    /// Still waiting for the pulse (the service checks before swelling the screen).
    var isPulsing: Bool { lock.lock(); defer { lock.unlock() }; if case .running = pulse, !paused { return true }; return false }

    /// The swell has started: from here the engine can judge it as soon as it peaks.
    func pulseStarted(_ schedule: FacePulse.Schedule, exposureHeld: Bool, learned: [[Double]]) {
        lock.lock(); defer { lock.unlock() }
        guard case .running = pulse else { return }
        pulseSchedule = schedule; pulseHeld = exposureHeld; pulseLearned = learned
    }

    /// The service ran the brightness pulse (nil when it couldn't). Judges it if that wasn't done at the peak, then
    /// unlocks or asks for a challenge.
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
        if verdict.reason == "no response to the light" { skipPulse = true }
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
