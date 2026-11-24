import Foundation
import os

/// Compares live frames with the enrolled face. Two good frames in a row is a match; then it has to show it's live
/// and isn't a photo or screen, as the security level says (`FaceSecurity`). About half a second of a visible face
/// that doesn't match is a "not recognized" verdict, and so is a face that stays refused (a rectangle edge around it,
/// or the spoof model sure it's fake).
///
/// Showing it's live, quietest first:
/// 1. The spoof model, which runs on every frame with a face from the start: once its last `spoofFrames` frames
///    average `liveLevel` or more, the match unlocks with nothing to do.
/// 2. The glow (Standard and More secure), when the spoof model isn't that sure: the service lights the screen,
///    calls `pulseStarted` as it begins and `finishPulse` once it's over. It's judged as soon as its last window has
///    passed; when it vouches and the spoof model is at least at `glowSpoofFloor`, that's the match. In harsh light
///    (direct sun, or a room the light sensor says is too bright: the service calls `skipPulse`) the glow is skipped,
///    and so it is for the rest of the scan once one got no response.
/// 3. A challenge: a blink, or on More secure a random blink, smile or head turn, with `challengeSeconds` to do it
///    once shown (looking away to turn doesn't count as a miss).
///
/// When the spoof model is sure the face is fake (`refuseLevel`), Faster refuses it. Standard and More secure doubt it
/// instead, since the model also calls real faces fake (a hood around the face, a dim room): the glow has to vouch
/// for the face's shape and then the challenge has to be done, both. Where the glow doesn't vouch, or got no response
/// earlier in the scan, the face is refused as before. In a room too bright for the glow, as in harsh light on the
/// face, the model's "fake" doesn't refuse: the challenge decides.
/// Runs on the camera queue; `finishPulse` may come from any thread.
final class ScanEngine: @unchecked Sendable {
    enum Event: Sendable {
        case face(Bool)
        /// The face matches and now has to do this to unlock; nil once it isn't waiting. `bright` when it's asked
        /// because the light is too bright for the quiet checks (sun on the face, or a bright room).
        case challenge(LivenessChallenge?, bright: Bool)
        /// The face matches and the spoof model's first frames are being gathered (a fraction of a second).
        case verifying
        /// The face matches but the spoof model isn't sure: run the glow, then call `finishPulse`.
        case pulse
        case pulseResult(FacePulse.Verdict)
        /// Went straight to a challenge without the glow, and why.
        case pulseSkipped(String)
        /// Unlocked: `via` says what vouched for it (spoof model, glow or challenge). `typical` is the median score of
        /// the face's frames in this attempt, for the adaptive threshold.
        case match(score: Float, embedding: [Float], via: String, typical: Float, pulse: FacePulse.Reading?)
        /// `refused` is true when it was a photo edge or the spoof model rather than a weak match.
        case noMatch(score: Float, refused: Bool)
        /// Mean frame brightness, a few times a second.
        case light(Double)
    }

    private static let log = Logger(subsystem: "com.marcogad.islet", category: "unlock")
    static let challengeSeconds = 8.0
    /// The glow should end within this; if the service never answers, fall back to a challenge.
    static let pulseSeconds = 5.0
    /// Frames needed at each light level to judge the glow before the service reports it over.
    static let earlyFrames = 4

    private enum PulseState { case idle, running(since: Date, frames: [FacePulse.Frame]), done }

    private let embedder: FaceEmbedder
    private let antiSpoof: AntiSpoofModel?
    private let enrolled: [[Float]]
    private let threshold: Float
    private let security: FaceSecurity
    private let onEvent: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var matches = 0, misses = 0, best: Float = 0
    private var paused = false
    private var lastFace: Bool?
    private var lastPrompt: LivenessChallenge?
    /// The last frame's light was harsh (sun on the face), for the prompt's wording.
    private var lightHarsh = false
    private var verifyingSent = false
    private var detector: ChallengeDetector
    private var frameCount = 0
    /// When the challenge was shown in this attempt.
    private var promptedAt: Date?
    private var faceLost = 0
    /// Recent frames that showed the face inside a rectangle (true) or not.
    private var framedHistory: [Bool] = []
    private var spoof = SpoofTracker()
    private var pulse = PulseState.idle
    /// The quiet checks couldn't vouch: the challenge now.
    private var fallback = false
    private var scores: [Float] = []
    private var lastMatch: (score: Float, embedding: [Float])?
    /// The running glow's light pattern, once the service started it, and what to judge it with.
    private var pulseSchedule: FacePulse.Schedule?
    private var pulseHeld = false
    private var pulseLearned: [[Double]] = []
    /// Recent frames lit harshly (direct sun).
    private var harshHistory: [Bool] = []
    /// A glow got no response, or the room is too bright, in this scan: later attempts skip it. Kept across
    /// `resume()`.
    private var skipGlow = false
    /// The light sensor says the room is too bright for the glow (FacePulse.glowMaxLux). Like harsh light on the face,
    /// the spoof model can't be trusted to refuse a real face then (it read 0.02 on the owner at ~4000 lux,
    /// 2026-11-24): the challenge decides. Kept across `resume()`.
    private var brightRoom = false
    /// The spoof model called this attempt's face fake and it's getting the glow and the challenge instead of a refusal.
    private var doubted = false

    /// `brightRoom`: the light sensor read more than the glow can work in when the scan started. Standard and More
    /// secure then skip the glow and don't wait on the spoof model: the challenge is asked as soon as the face matches.
    init(embedder: FaceEmbedder, antiSpoof: AntiSpoofModel?, enrolled: [[Float]], threshold: Float, security: FaceSecurity,
         brightRoom: Bool = false, onEvent: @escaping @Sendable (Event) -> Void) {
        self.embedder = embedder
        self.antiSpoof = antiSpoof
        self.enrolled = enrolled
        self.threshold = threshold
        self.security = security
        self.onEvent = onEvent
        if brightRoom && security.usesGlow { self.brightRoom = true; skipGlow = true }
        detector = ChallengeDetector(Self.pick(security))
    }

    /// More secure picks a new random challenge for every attempt; the others always ask for a blink.
    static func pick(_ security: FaceSecurity) -> LivenessChallenge {
        security.randomChallenge ? LivenessChallenge.allCases.randomElement() ?? .blink : .blink
    }

    /// After a verdict the engine ignores frames until `resume()`.
    func resume() {
        lock.lock(); defer { lock.unlock() }
        paused = false; matches = 0; misses = 0; best = 0; framedHistory = []
        detector = ChallengeDetector(Self.pick(security)); promptedAt = nil
        spoof.reset(); pulse = .idle; fallback = false; scores = []; lastMatch = nil
        pulseSchedule = nil; harshHistory = []; doubted = false; verifyingSent = false; lastPrompt = nil
    }
    func pause() { lock.lock(); paused = true; lock.unlock() }

    /// `light` is the frame's mean brightness when it was measured for this frame.
    func handle(_ analysis: FaceAnalysis?, light: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let light { onEvent(.light(light)) }
        guard !paused else { return }
        let now = Date()
        guard let a = analysis, a.boxWidth > FaceAnalysis.minimumWidth, let image = a.alignedImage(), let e = embedder.embed(image) else {
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
        if fallback && promptedAt != nil {
            detector.add(openness: a.eyeOpenness, mouth: a.mouthWidth, yaw: a.proxyX)
        }
        framedHistory.append(a.framed)
        if framedHistory.count > 10 { framedHistory.removeFirst() }
        let framed = framedHistory.filter { $0 }.count >= 4
        // Every frame: the quiet check has to be quick to be worth it.
        if let antiSpoof, let live = antiSpoof.live(a.pixelBuffer, face: a.box) { spoof.add(live) }
        if let l = FacePulse.lighting(a.pixelBuffer, points: a.points, face: a.box) {
            harshHistory.append(l.harsh)
            if harshHistory.count > 6 { harshHistory.removeFirst() }
        }
        let harsh = harshHistory.count >= 3 && harshHistory.filter { $0 }.count * 2 > harshHistory.count
        lightHarsh = harsh
        let spoofVerdict = spoof.verdict(security)
        // In harsh light the spoof model can't be trusted to refuse a real face; the challenge decides instead.
        let fake = spoofVerdict == .spoof && !harsh && !brightRoom
        // Also while a glow is already running: it often starts while the model is only unsure, and the model turns
        // sure a few frames later. Refusing then cut the glow off before it could judge (2026-11-24).
        let glowOpen: Bool = { if case .done = pulse { return false }; return true }()
        if fake, !doubted, !framed, security.usesGlow, !skipGlow, !fallback, glowOpen {
            doubted = true
            Self.log.notice("doubted: spoof model \(self.spoof.mean(last: SpoofTracker.refuseFrames) ?? -1)")
        }
        let refused = framed || (fake && !doubted)

        let score = FaceMatcher.score(e, enrolled: enrolled)
        best = max(best, score)
        scores.append(score)
        frameCount += 1
        // For tuning the range (1.7.1): how wide the face was, how well it matched, what the spoof model made of it.
        if frameCount % 10 == 1 {
            Self.log.notice("frame \(self.frameCount): width \(a.boxWidth, format: .fixed(precision: 3)) score \(score, format: .fixed(precision: 2)) spoof \(self.spoof.mean(last: SpoofTracker.refuseFrames) ?? -1, format: .fixed(precision: 2))")
        }
        if score >= threshold { lastMatch = (score, e) }
        if case .running = pulse, harsh, pulseSchedule == nil {
            // The sun came out before the glow started: don't bother with it.
            pulse = .done; fallback = true
            onEvent(.pulseSkipped("harsh light"))
        }
        if case .running(let since, var frames) = pulse {
            let m = FacePulse.measure(a.pixelBuffer, points: a.points, face: a.box)
            frames.append(FacePulse.Frame(time: FaceCamera.captured(a.pixelBuffer), face: m.face, background: m.background,
                                          matched: score >= threshold && !refused))
            pulse = .running(since: since, frames: frames)
            if now.timeIntervalSince(since) > Self.pulseSeconds { finishPulseLocked(nil, exposureHeld: false, learned: []); return }
            // Judge as soon as the last window has passed, rather than waiting for the light to go back.
            if let schedule = pulseSchedule, let taken = frames.last?.time, taken >= schedule.ready,
               frames.filter({ schedule.inHigh($0.time) }).count >= Self.earlyFrames,
               frames.filter({ schedule.inLow($0.time) }).count >= Self.earlyFrames {
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
            if matches >= 2 { matched(score: score, embedding: e, spoofVerdict: spoofVerdict, harsh: harsh, now: now) }
            if paused { return }
        } else {
            matches = 0
            // While the challenge or the glow is on, a turned face or a changing light may not match; only the time
            // limits end it.
            if promptedAt == nil && !pulsing { misses += 1 }
        }
        if let at = promptedAt, now.timeIntervalSince(at) > Self.challengeSeconds { misses = 8 }
        if misses >= 8 {
            if refused {
                Self.log.notice("refused by \(framed ? "a photo edge" : "the spoof model", privacy: .public) \(self.spoof.mean(last: SpoofTracker.refuseFrames) ?? -1)")
            }
            paused = true; prompt(nil)
            onEvent(.noMatch(score: refused ? 0 : best, refused: refused)); best = 0
        }
    }

    /// The face matches: the next step towards showing it's live.
    private func matched(score: Float, embedding e: [Float], spoofVerdict: SpoofTracker.Verdict, harsh: Bool, now: Date) {
        if fallback {
            if detector.done { finish(score: score, embedding: e, via: "challenge", pulse: nil); return }
            if promptedAt == nil { promptedAt = now }
            prompt(detector.challenge)
            return
        }
        if case .running = pulse { return } // the glow decides
        if doubted {
            // Fake by the spoof model: the glow first, whatever the model says now, then the challenge.
            if case .idle = pulse { pulse = .running(since: now, frames: []); onEvent(.pulse) }
            return
        }
        if spoofVerdict == .live { finish(score: score, embedding: e, via: "spoof model", pulse: nil); return }
        // Still gathering the spoof model's frames (a fraction of a second): wait for them, unless the room is too
        // bright to trust them anyway.
        if spoofVerdict == .unknown, antiSpoof != nil, !brightRoom {
            if !verifyingSent { verifyingSent = true; onEvent(.verifying) }
            return
        }
        if security.usesGlow, case .idle = pulse, !harsh, !skipGlow {
            pulse = .running(since: now, frames: [])
            onEvent(.pulse)
            return
        }
        if security.usesGlow, case .idle = pulse {
            onEvent(.pulseSkipped(harsh ? "harsh light" : brightRoom ? "bright room" : "no response earlier"))
        }
        pulse = .done
        fallback = true
        promptedAt = now
        prompt(detector.challenge)
    }

    /// Still waiting for the glow (the service checks before lighting the screen).
    var isPulsing: Bool { lock.lock(); defer { lock.unlock() }; if case .running = pulse, !paused { return true }; return false }

    /// The room is too bright for the screen's light to tell anything: a challenge now, and no glow for the rest of
    /// the scan.
    func skipPulse(_ why: String) {
        lock.lock(); defer { lock.unlock() }
        guard case .running = pulse, !paused else { return }
        pulse = .done; fallback = true; skipGlow = true; brightRoom = true
        onEvent(.pulseSkipped(why))
        // A doubted face gets the challenge too: in this light the model's "fake" isn't to be trusted.
        doubted = false
        promptedAt = Date()
        prompt(detector.challenge)
    }

    /// The light pattern has started: from here the engine can judge it as soon as its last window has passed.
    func pulseStarted(_ schedule: FacePulse.Schedule, exposureHeld: Bool, learned: [[Double]]) {
        lock.lock(); defer { lock.unlock() }
        guard case .running = pulse else { return }
        pulseSchedule = schedule; pulseHeld = exposureHeld; pulseLearned = learned
    }

    /// The service ran the glow (nil when it couldn't). Judges it if that wasn't done already, then unlocks or asks
    /// for the challenge.
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
        if verdict.reason == "no response to the light" { skipGlow = true }
        if doubted {
            // The spoof model said fake: the glow vouching isn't enough on its own, the challenge has to follow. A
            // glow that doesn't vouch refuses it, as the model would have.
            guard case .passed = verdict, faceLost == 0, lastMatch != nil else { refuse(); return }
            fallback = true
            promptedAt = Date()
            prompt(detector.challenge)
            return
        }
        let spoofOK = antiSpoof == nil || (spoof.mean(last: min(security.spoofFrames, spoof.values.count)) ?? 0) >= security.glowSpoofFloor
        if case .passed(let reading) = verdict, spoofOK, faceLost == 0, let m = lastMatch {
            finish(score: m.score, embedding: m.embedding, via: "glow", pulse: reading)
            return
        }
        // Couldn't vouch for it quietly: the challenge.
        fallback = true
        promptedAt = Date()
        prompt(detector.challenge)
    }

    /// A doubted face the glow couldn't vouch for: refused, like a photo.
    private func refuse() {
        paused = true
        prompt(nil)
        onEvent(.noMatch(score: 0, refused: true)); best = 0
    }

    private func finish(score: Float, embedding: [Float], via: String, pulse reading: FacePulse.Reading?) {
        paused = true
        prompt(nil)
        let typical = FaceMatcher.median(scores) ?? score
        onEvent(.match(score: score, embedding: embedding, via: via, typical: typical, pulse: reading))
    }

    private func report(face: Bool) {
        guard lastFace != face else { return }
        lastFace = face
        onEvent(.face(face))
    }

    private func prompt(_ challenge: LivenessChallenge?) {
        guard lastPrompt != challenge else { return }
        lastPrompt = challenge
        onEvent(.challenge(challenge, bright: challenge != nil && (brightRoom || lightHarsh)))
    }
}
