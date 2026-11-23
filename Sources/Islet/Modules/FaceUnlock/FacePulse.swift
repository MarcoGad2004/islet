import CoreVideo
import Foundation

/// The screen-light depth check. Once the face matches, the display brightness swells smoothly once (up when there's
/// room, otherwise down) and comes back. The screen is the light nearest the face, so a real head changes in a
/// pattern set by its shape:
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
    /// Correlation with the learned pattern needed once there's one.
    static let minAgreement = 0.7
    /// Learned patterns needed before they're checked.
    static let profileMinimum = 8
    /// Frames in the windows where the face still matched: no swapping faces mid-pulse.
    static let minMatched = 0.7

    struct Schedule: Sendable, Equatable {
        /// When the ramp started.
        var start: Date
        var brighter: Bool
        func inBaseline(_ t: Date) -> Bool { t >= start.addingTimeInterval(-0.3) && t <= start }
        func inPeak(_ t: Date) -> Bool {
            t >= start.addingTimeInterval(FacePulse.rise + 0.08) && t <= start.addingTimeInterval(FacePulse.rise + FacePulse.hold)
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
        /// Linear brightness of the frame's top corners, away from the face.
        var background: Double?
        /// The face in this frame matched the enrolment.
        var matched: Bool
    }

    struct Reading: Sendable, Equatable {
        var contrast: Double
        var shape: Double
        /// Each patch's change relative to the centre's, for learning the owner's pattern. Nil if a patch was missing.
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

    /// Judges a pulse from the frames recorded around it. `exposureHeld` means the camera's exposure was locked, so
    /// without a background reading the raw change still counts.
    static func judge(_ frames: [Frame], schedule: Schedule, exposureHeld: Bool, learned: [[Double]]) -> Verdict {
        let base = frames.filter { schedule.inBaseline($0.time) }, peak = frames.filter { schedule.inPeak($0.time) }
        guard base.count >= 3, peak.count >= 3 else { return .inconclusive("too few frames", nil) }
        let windows = base + peak
        let matched = Double(windows.filter(\.matched).count) / Double(windows.count)

        let bgBase = median(base.compactMap(\.background)), bgPeak = median(peak.compactMap(\.background))
        let bgGain: Double
        if let b = bgBase, let p = bgPeak, b > 0 { bgGain = p / b } else if exposureHeld { bgGain = 1 } else {
            return .inconclusive("no background", nil)
        }
        let sign = schedule.brighter ? 1.0 : -1.0
        // The change of each patch beyond the background's, positive in the pulse's direction.
        let change: [Double?] = Patch.allCases.map { patch in
            guard let b = median(base.compactMap { $0.face[patch.rawValue] }),
                  let p = median(peak.compactMap { $0.face[patch.rawValue] }), b > 0 else { return nil }
            return (p / b / bgGain - 1) * sign
        }
        let c = centre.compactMap { change[$0.rawValue] }, s = sides.compactMap { change[$0.rawValue] }
        guard c.count >= 2, !s.isEmpty else { return .inconclusive("face not fully in view", nil) }
        let contrast = c.reduce(0, +) / Double(c.count)
        let side = s.reduce(0, +) / Double(s.count)
        let shape = contrast > 0.005 ? (contrast - side) / contrast : 0
        let profile = change.allSatisfy { $0 != nil } && contrast > 0.005 ? change.map { $0! / contrast } : nil
        let learnedMean = learned.count >= profileMinimum ? meanProfile(learned) : nil
        let agreement = zip2(profile, learnedMean).map { correlation($0, $1) }
        let reading = Reading(contrast: contrast, shape: shape, profile: profile, agreement: agreement, matched: matched)

        if matched < minMatched { return .inconclusive("face changed", reading) }
        if contrast < minContrast { return .inconclusive("no response to the light", reading) }
        if shape < minShape { return .inconclusive("flat", reading) }
        if learnedMean != nil {
            guard let agreement, agreement >= minAgreement else { return .inconclusive("not your usual shape", reading) }
        }
        return .passed(reading)
    }

    // MARK: Measuring

    /// Reads the patches for one frame. `points` are FaceAnalysis.points: eyes (left, right), nose, mouth corners,
    /// in image coordinates with a bottom-left origin.
    static func measure(_ pb: CVPixelBuffer, points: [CGPoint], face box: CGRect) -> (face: [Double?], background: Double?) {
        guard points.count == 5, CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else {
            return (Array(repeating: nil, count: Patch.allCases.count), nil)
        }
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return (Array(repeating: nil, count: Patch.allCases.count), nil) }
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

        // The top corners, unless the face reaches into them.
        let r = Double(w) * 0.05
        let corners = [CGPoint(x: Double(w) * 0.08, y: Double(h) * 0.92), CGPoint(x: Double(w) * 0.92, y: Double(h) * 0.92)]
        let faceRect = CGRect(x: box.minX * Double(w), y: box.minY * Double(h), width: box.width * Double(w), height: box.height * Double(h))
            .insetBy(dx: -r * 2, dy: -r * 2)
        let bg = corners.filter { !faceRect.contains($0) }.compactMap { patch($0, radius: r) }
        return (face, bg.isEmpty ? nil : bg.reduce(0, +) / Double(bg.count))
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

        /// Sun on the face: one side far brighter than the other, or much of the skin blown out. The screen's light
        /// is lost in it, and a texture model sees an unusual face.
        var harsh: Bool { sideRatio >= Lighting.harshSideRatio || clipped >= Lighting.harshClipped }
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
        var clipped = 0.0, n = 0.0
        for j in 0..<12 {
            for i in 0..<12 {
                guard let v = luma(fx + fw * (0.15 + 0.7 * Double(i) / 11), fy + fh * (0.1 + 0.75 * Double(j) / 11)) else { continue }
                n += 1
                if v > 0.96 { clipped += 1 }
            }
        }
        return Lighting(sideRatio: min(ratio, 99), clipped: n > 0 ? clipped / n : 0)
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
