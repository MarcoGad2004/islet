import CoreVideo
import Foundation

/// The screen-light depth check. Once the face matches, the screen lights the face in a pattern the scan knows and
/// compares the frames at its lower and higher light. Normally that's the glow (`Glow`, drawn by `FaceGlow`): a
/// full-screen layer of white that fades in, steps between two levels in a random order and fades out, its strength
/// set by the room's light. Where it can't be drawn, the display brightness swells once instead (`Schedule.swell`).
/// The screen is the light nearest the face, so a real head changes in a pattern set by its shape:
/// - the face, ~50 cm away, changes far more than the background behind it (`contrast`);
/// - the parts facing the screen (forehead, nose, chin) change more than the sides turned away from it (`shape`).
/// A phone or tablet makes its own light, so it barely changes (low contrast). A printed photo is flat, so every part
/// of it changes alike (low shape). Over time the owner's own pattern is learned (`profile`), which a mask with a
/// different shape is unlikely to match. All of it is measured as ratios, so camera exposure doesn't cancel it out.
/// The check never refuses a face on its own: when it can't vouch (a bright room, a screen) the scan asks for a
/// challenge instead.
enum FacePulse {
    /// How far the brightness moves (0...1 scale): enough to measure, gentle enough to look like the screen waking.
    static let change = 0.3
    static let rise = 0.25, hold = 0.35, fall = 0.3
    /// Wait after holding the exposure before the swell: it settles, and the moment can't be predicted.
    static let lead = 0.3...0.45

    static let minContrast = 0.05
    static let minShape = 0.15
    /// Without a readable background: how much more the centre of the face must change than its sides.
    static let minRelative = 0.04
    /// Correlation with the learned pattern needed once there's one.
    static let minAgreement = 0.7
    /// Learned patterns needed before they're checked.
    static let profileMinimum = 8
    /// Frames in the windows where the face still matched: no swapping faces mid-pulse.
    static let minMatched = 0.7

    /// When the face was lit less and more, once the light had settled (display and camera lag included): frames in
    /// `low` are compared with frames in `high`.
    struct Schedule: Sendable, Equatable {
        var low: [ClosedRange<Date>]
        var high: [ClosedRange<Date>]
        /// From here on it can be judged: the last window has ended.
        var ready: Date
        func inLow(_ t: Date) -> Bool { low.contains { $0.contains(t) } }
        func inHigh(_ t: Date) -> Bool { high.contains { $0.contains(t) } }

        /// The brightness swell starting at `start`: the moment before it against its peak. When it dims, the moment
        /// before is the brighter one. Judged after a few peak frames rather than once it's back.
        static func swell(start: Date, brighter: Bool) -> Schedule {
            let before = start.addingTimeInterval(-0.3)...start
            let peak = start.addingTimeInterval(FacePulse.rise + 0.08)...start.addingTimeInterval(FacePulse.rise + FacePulse.hold)
            return Schedule(low: [brighter ? before : peak], high: [brighter ? peak : before],
                            ready: start.addingTimeInterval(FacePulse.rise + 0.22))
        }
    }

    // MARK: The glow

    /// Fade in and out, each step between levels, and each level's hold. A step every 0.43 s at most: well under
    /// three changes a second, and every edge eased, so it breathes rather than flashes.
    static let glowFade = 0.3, glowStep = 0.15, glowHold = 0.28
    /// Display and camera lag before a hold's frames count.
    static let glowSettle = 0.08
    /// Above this (lux at the bezel) the screen's light is lost in the room's: skip it and ask for a challenge.
    static let glowMaxLux = 1500.0
    /// The higher level over the lower: the change the camera reads.
    static let glowRatio = 1.6

    /// How strong the glow's higher level is, as a share of the panel's peak brightness, for the room's light. The face
    /// has to change by a share of the light already on it, so a dim room needs little (where a bright glow would
    /// glare most) and a bright one a lot; nil when it's too bright for the screen to tell. ~0.24 lux at 50 cm per
    /// nit of a 14" screen: at 500 lux the step is ~340 nits, ~80 lux, ~16% of the room's.
    static func glowShare(lux: Double?) -> Double? {
        guard let lux else { return 0.3 } // no sensor: a middling room
        guard lux <= glowMaxLux else { return nil }
        return min(0.08 + lux / 2000, 0.65)
    }

    /// Four steps after the first hold at the lower level, in a random order: at least two up and one down, so a
    /// replayed video can't know when to brighten.
    static func glowSteps() -> [Bool] {
        while true {
            let s = (0..<4).map { _ in Bool.random() }
            if s.filter({ $0 }).count >= 2, s.contains(false) { return s }
        }
    }

    struct Glow: Sendable, Equatable {
        /// Pixel values: 1 is SDR white; above it is the XDR panel's extra brightness.
        var low: Double
        var high: Double
        /// After the first hold at `low`: true = up to `high`.
        var steps: [Bool]

        /// Levels for a share of the panel's peak. `potential` is the display's
        /// `maximumPotentialExtendedDynamicRangeColorComponentValue` (its peak over SDR white at the current
        /// brightness), `headroom` what it allows now. The lower level is at least SDR white so the screen never
        /// darkens; the higher one stays within the headroom so the step isn't clipped away.
        init(share: Double, potential: Double, headroom: Double, steps: [Bool] = FacePulse.glowSteps()) {
            let top = max(headroom, 1)
            high = min(max(share * max(potential, 1), FacePulse.glowRatio), top)
            low = min(max(1, 0.35 * high), high / FacePulse.glowRatio)
            self.steps = steps
        }

        private static var segment: Double { FacePulse.glowStep + FacePulse.glowHold }
        private var stepsStart: Double { FacePulse.glowFade + FacePulse.glowHold }
        /// Until it starts fading out.
        var length: Double { stepsStart + Double(steps.count) * Self.segment }
        var total: Double { length + FacePulse.glowFade }
        private func level(_ up: Bool) -> Double { up ? high : low }

        /// The pixel value and coverage `t` seconds after it started.
        func at(_ t: Double) -> (value: Double, alpha: Double) {
            func ease(_ x: Double) -> Double { let x = min(max(x, 0), 1); return x * x * (3 - 2 * x) }
            if t < FacePulse.glowFade { return (low, ease(t / FacePulse.glowFade)) }
            if t >= length { return (level(steps.last ?? false), 1 - ease((t - length) / FacePulse.glowFade)) }
            let after = t - stepsStart
            guard after >= 0 else { return (low, 1) }
            let i = min(Int(after / Self.segment), steps.count - 1)
            let from = i == 0 ? low : level(steps[i - 1]), to = level(steps[i])
            return (from + (to - from) * ease((after - Double(i) * Self.segment) / FacePulse.glowStep), 1)
        }

        func schedule(start: Date) -> Schedule {
            func at(_ t: Double) -> Date { start.addingTimeInterval(t) }
            var low = [at(FacePulse.glowFade + FacePulse.glowSettle)...at(stepsStart)], high: [ClosedRange<Date>] = []
            for (i, up) in steps.enumerated() {
                let s = stepsStart + Double(i) * Self.segment
                let window = at(s + FacePulse.glowStep + FacePulse.glowSettle)...at(s + Self.segment)
                if up { high.append(window) } else { low.append(window) }
            }
            return Schedule(low: low, high: high, ready: at(length))
        }
    }

    /// Where the light is read on the face. Centre parts face the screen; sides turn away from it.
    enum Patch: Int, CaseIterable { case forehead, nose, chin, leftCheek, rightCheek, leftSide, rightSide }
    static let centre: [Patch] = [.forehead, .nose, .chin]
    static let sides: [Patch] = [.leftSide, .rightSide]

    struct Frame: Sendable {
        var time: Date
        /// Linear brightness per `Patch`, nil where it was off the frame or clipped.
        var face: [Double?]
        /// Linear brightness of spots around the head (`backgroundSpots`), nil where blown out, dark or covered.
        var background: [Double?]
        /// The face in this frame matched the enrolment.
        var matched: Bool
        /// Mean brightness of the whole frame (gamma), for Check Light's record only.
        var luma: Double? = nil
    }

    struct Reading: Sendable, Equatable {
        /// The face's change beyond the background's; nil when no background spot could be read.
        var contrast: Double?
        var shape: Double?
        /// The centre of the face's change beyond its sides': needs no background and isn't affected by exposure.
        var relative: Double
        /// Each patch's change beyond the sides', over the centre's, for learning the owner's pattern. Nil if a patch
        /// was missing.
        var profile: [Double]?
        /// Correlation with the learned pattern, when there's one.
        var agreement: Double?
        var matched: Double
    }

    enum Verdict: Sendable, Equatable {
        case passed(Reading)
        case inconclusive(String, Reading?)

        var passed: Bool { if case .passed = self { true } else { false } }
        var reason: String? { if case .inconclusive(let why, _) = self { why } else { nil } }

        var reading: Reading? {
            switch self {
            case .passed(let r): r
            case .inconclusive(_, let r): r
            }
        }
    }

    /// Judges a pulse from the frames recorded around it: each patch's gain is its typical level in the `high` windows
    /// over the `low` ones. `exposureHeld` means the camera's exposure was locked (the
    /// MacBook camera doesn't allow it), so the raw change is real and the background isn't needed to correct it.
    ///
    /// With a readable background the face's change is measured against the room's (`contrast`, `shape`). Without
    /// one (blown-out lights or windows, a dark room) it falls back to the centre of the face against its sides
    /// (`relative`), which exposure changes don't affect and a flat print or a screen doesn't show.
    static func judge(_ frames: [Frame], schedule: Schedule, exposureHeld: Bool, learned: [[Double]]) -> Verdict {
        let base = frames.filter { schedule.inLow($0.time) }, peak = frames.filter { schedule.inHigh($0.time) }
        guard base.count >= 3, peak.count >= 3 else { return .inconclusive("too few frames", nil) }
        let windows = base + peak
        let matched = Double(windows.filter(\.matched).count) / Double(windows.count)

        // Each background spot's own change, then the typical one: spots that are blown out or covered are skipped.
        let spots = frames.map(\.background.count).max() ?? 0
        let bgRatios: [Double] = (0..<spots).compactMap { i in
            func level(_ fs: [Frame]) -> Double? {
                let v = fs.compactMap { i < $0.background.count ? $0.background[i] : nil }
                return v.count >= 2 ? median(v) : nil
            }
            guard let b = level(base), let p = level(peak), b > 0 else { return nil }
            return p / b
        }
        let bgGain = median(bgRatios) ?? (exposureHeld ? 1 : nil)

        // Each patch's raw gain over the swell.
        let gain: [Double?] = Patch.allCases.map { patch in
            guard let b = median(base.compactMap { $0.face[patch.rawValue] }),
                  let p = median(peak.compactMap { $0.face[patch.rawValue] }), b > 0 else { return nil }
            return p / b
        }
        let c = centre.compactMap { gain[$0.rawValue] }, s = sides.compactMap { gain[$0.rawValue] }
        guard c.count >= 2, !s.isEmpty else { return .inconclusive("face not fully in view", nil) }
        let gc = c.reduce(0, +) / Double(c.count), gs = s.reduce(0, +) / Double(s.count)
        let relative = gc / gs - 1
        let profile = gain.allSatisfy { $0 != nil } && relative > 0.005 ? gain.map { ($0! / gs - 1) / relative } : nil
        var contrast: Double?, shape: Double?
        if let bgGain {
            let cc = gc / bgGain - 1, sc = gs / bgGain - 1
            contrast = cc
            shape = cc > 0.005 ? (cc - sc) / cc : 0
        }
        let learnedMean = learned.count >= profileMinimum ? meanProfile(learned) : nil
        let agreement = zip2(profile, learnedMean).map { correlation($0, $1) }
        let reading = Reading(contrast: contrast, shape: shape, relative: relative, profile: profile, agreement: agreement, matched: matched)

        if matched < minMatched { return .inconclusive("face changed", reading) }
        if let contrast, let shape {
            if contrast < minContrast { return .inconclusive("no response to the light", reading) }
            if shape < minShape { return .inconclusive("flat", reading) }
        } else if relative < minRelative {
            return .inconclusive("flat", reading)
        }
        if learnedMean != nil {
            guard let agreement, agreement >= minAgreement else { return .inconclusive("not your usual shape", reading) }
        }
        return .passed(reading)
    }

    // MARK: Measuring

    /// Reads the patches for one frame. `points` are FaceAnalysis.points: eyes (left, right), nose, mouth corners,
    /// in image coordinates with a bottom-left origin.
    static func measure(_ pb: CVPixelBuffer, points: [CGPoint], face box: CGRect) -> (face: [Double?], background: [Double?]) {
        let none: ([Double?], [Double?]) = (Array(repeating: nil, count: Patch.allCases.count), [])
        guard points.count == 5, CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else { return none }
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return none }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
        let px = base.assumingMemoryBound(to: UInt8.self)

        /// Mean linear brightness of a square around `c` (bottom-left origin), or nil if off the frame or clipped.
        func patch(_ c: CGPoint, radius r: Double) -> Double? {
            guard r >= 1, c.x - r >= 0, c.y - r >= 0, c.x + r < Double(w), c.y + r < Double(h) else { return nil }
            var sum = 0.0, gammaSum = 0.0, n = 0.0
            for j in -2...2 {
                for i in -2...2 {
                    let x = Int(c.x + Double(i) * r / 2), y = h - 1 - Int(c.y + Double(j) * r / 2)
                    let o = y * row + x * 4
                    let v = (0.114 * Double(px[o]) + 0.587 * Double(px[o + 1]) + 0.299 * Double(px[o + 2])) / 255
                    gammaSum += v; sum += pow(v, 2.2); n += 1
                }
            }
            let g = gammaSum / n
            return g > 0.94 || g < 0.02 ? nil : sum / n
        }

        let (centres, ed) = patchCentres(points)
        let face = Patch.allCases.map { patch(centres[$0]!, radius: 0.1 * ed) }

        let r = Double(w) * 0.03
        let bg = backgroundSpots(face: box).map { $0.flatMap { patch(CGPoint(x: $0.x * Double(w), y: $0.y * Double(h)), radius: r) } }
        return (face, bg)
    }

    /// Spots in the room behind the head (normalized, bottom-left origin): a 6x3 grid over the upper frame, leaving out
    /// the face and the body below it (nil). Always the same count and order, so frames can be compared spot by spot.
    static func backgroundSpots(face box: CGRect) -> [CGPoint?] {
        let xs = [0.06, 0.22, 0.38, 0.62, 0.78, 0.94], ys = [0.92, 0.75, 0.58]
        let left = box.minX - box.width * 0.5, right = box.maxX + box.width * 0.5, top = box.maxY + box.height * 0.25
        return ys.flatMap { y in
            xs.map { x -> CGPoint? in x > left && x < right && y < top ? nil : CGPoint(x: x, y: y) }
        }
    }

    /// Where each patch sits on the face, and the eye distance. `points` as in `measure`.
    private static func patchCentres(_ points: [CGPoint]) -> ([Patch: CGPoint], Double) {
        let eL = points[0], eR = points[1], nose = points[2], m1 = points[3], m2 = points[4]
        let ed = max(hypot(eR.x - eL.x, eR.y - eL.y), 1)
        let u = CGPoint(x: (eR.x - eL.x) / ed, y: (eR.y - eL.y) / ed), v = CGPoint(x: -u.y, y: u.x)
        let eyeMid = CGPoint(x: (eL.x + eR.x) / 2, y: (eL.y + eR.y) / 2)
        let mouthMid = CGPoint(x: (m1.x + m2.x) / 2, y: (m1.y + m2.y) / 2)
        func at(_ p: CGPoint, _ a: Double, _ b: Double) -> CGPoint { CGPoint(x: p.x + u.x * a * ed + v.x * b * ed, y: p.y + u.y * a * ed + v.y * b * ed) }
        return ([
            .forehead: at(eyeMid, 0, 0.55), .nose: nose, .chin: at(mouthMid, 0, -0.45),
            .leftCheek: at(eL, 0, -0.55), .rightCheek: at(eR, 0, -0.55),
            .leftSide: at(eyeMid, -0.85, -0.3), .rightSide: at(eyeMid, 0.85, -0.3),
        ], ed)
    }

    // MARK: Harsh light

    /// How the face is lit in one frame, to spot direct sun before trying the pulse.
    struct Lighting: Sendable, Equatable {
        /// Brighter side of the face over the darker, in linear light (1 = even).
        var sideRatio: Double
        /// Share of the face's pixels blown out to white.
        var clipped: Double

        /// Mean brightness (gamma, 0...1) of the face's middle and of the frame outside the face (the room behind it).
        var faceLuma = 0.5
        var backgroundLuma = 0.5
        /// Brighter background over the face, in linear light (a window behind the face).
        var backlightRatio: Double { pow(backgroundLuma, 2.2) / max(pow(faceLuma, 2.2), 0.0005) }

        /// A bright window or lamp behind the face: auto-exposure sets for it and the face goes dark and flat. The spoof
        /// model reads that as a print (owner, 2026-11-25: "fake" with the blinds open, 1.00 with them closed, same room).
        var backlit: Bool {
            backlightRatio >= Lighting.backlitRatio && faceLuma < Lighting.backlitFaceMax && backgroundLuma >= Lighting.backlitBackgroundMin
        }
        static let backlitRatio = 2.5
        static let backlitFaceMax = 0.45
        static let backlitBackgroundMin = 0.4

        /// Sun on the face (one side far brighter than the other, or much of the skin blown out) or a backlit face.
        /// The screen's light is lost in sun, and a texture model sees an unusual face in either.
        var harsh: Bool { sideRatio >= Lighting.harshSideRatio || clipped >= Lighting.harshClipped || backlit }
        static let harshSideRatio = 3.0
        static let harshClipped = 0.06
    }

    /// Reads the lighting of the face: its two sides (cheek and side patches) and a grid over the face box.
    static func lighting(_ pb: CVPixelBuffer, points: [CGPoint], face box: CGRect) -> Lighting? {
        guard points.count == 5, CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
        let px = base.assumingMemoryBound(to: UInt8.self)
        /// Gamma luma (0...1) at a point with a bottom-left origin, or nil off the frame.
        func luma(_ x: Double, _ y: Double) -> Double? {
            guard x >= 0, y >= 0, x < Double(w), y < Double(h) else { return nil }
            let o = (h - 1 - Int(y)) * row + Int(x) * 4
            return (0.114 * Double(px[o]) + 0.587 * Double(px[o + 1]) + 0.299 * Double(px[o + 2])) / 255
        }
        let (centres, ed) = patchCentres(points)
        func side(_ patches: [Patch]) -> Double? {
            let r = 0.1 * ed
            var sum = 0.0, n = 0.0
            for p in patches {
                guard let c = centres[p] else { continue }
                for j in -2...2 {
                    for i in -2...2 {
                        let x: Double = c.x + Double(i) * r / 2, y: Double = c.y + Double(j) * r / 2
                        if let v = luma(x, y) { sum += pow(v, 2.2); n += 1 }
                    }
                }
            }
            return n > 0 ? sum / n : nil
        }
        guard let l = side([.leftCheek, .leftSide]), let r = side([.rightCheek, .rightSide]) else { return nil }
        let ratio = max(l, r) / max(min(l, r), 0.0005)

        // A 12x12 grid over the middle of the face box (inset so hair and background stay out).
        let fx = box.minX * Double(w), fy = box.minY * Double(h), fw = box.width * Double(w), fh = box.height * Double(h)
        var clipped = 0.0, n = 0.0, faceSum = 0.0
        for j in 0..<12 {
            for i in 0..<12 {
                guard let v = luma(fx + fw * (0.15 + 0.7 * Double(i) / 11), fy + fh * (0.1 + 0.75 * Double(j) / 11)) else { continue }
                n += 1
                faceSum += pow(v, 2.2)
                if v > 0.96 { clipped += 1 }
            }
        }
        // The room: a sparse grid over the frame, skipping the face and the hair and neck round it (1.6x the box).
        var bgSum = 0.0, bgN = 0.0
        for j in 0..<12 {
            for i in 0..<16 {
                let x = (Double(i) + 0.5) * Double(w) / 16, y = (Double(j) + 0.5) * Double(h) / 12
                if abs(x - (fx + fw / 2)) < fw * 0.8 && abs(y - (fy + fh / 2)) < fh * 0.8 { continue }
                if let v = luma(x, y) { bgSum += pow(v, 2.2); bgN += 1 }
            }
        }
        let faceLin = n > 0 ? faceSum / n : 0.5, bgLin = bgN > 0 ? bgSum / bgN : faceLin
        return Lighting(sideRatio: min(ratio, 99), clipped: n > 0 ? clipped / n : 0,
                        faceLuma: pow(faceLin, 1 / 2.2), backgroundLuma: pow(bgLin, 1 / 2.2))
    }

    // MARK: Maths

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    static func meanProfile(_ list: [[Double]]) -> [Double]? {
        guard let n = list.first?.count, list.allSatisfy({ $0.count == n }) else { return nil }
        return (0..<n).map { i in list.map { $0[i] }.reduce(0, +) / Double(list.count) }
    }

    /// Pearson correlation of two equal-length vectors; 0 when either is constant.
    static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 1 else { return 0 }
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var num = 0.0, da = 0.0, db = 0.0
        for (x, y) in zip(a, b) { num += (x - ma) * (y - mb); da += (x - ma) * (x - ma); db += (y - mb) * (y - mb) }
        return da > 0 && db > 0 ? num / (da * db).squareRoot() : 0
    }

    private static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}

/// Collects pulse frames on the camera queue for Test recognition.
final class PulseRecorder: @unchecked Sendable {
    private var frames: [FacePulse.Frame] = []
    private var recording = false
    private let lock = NSLock()
    func begin() { lock.lock(); frames = []; recording = true; lock.unlock() }
    var isRecording: Bool { lock.lock(); defer { lock.unlock() }; return recording }
    func add(_ f: FacePulse.Frame) { lock.lock(); if recording { frames.append(f) }; lock.unlock() }
    func end() -> [FacePulse.Frame] { lock.lock(); defer { lock.unlock() }; recording = false; return frames }
}
