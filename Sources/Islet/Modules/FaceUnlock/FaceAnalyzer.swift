import CoreImage
import os
import Vision

/// What we learn about a face in one frame.
struct FaceAnalysis: @unchecked Sendable {
    /// Nose offset from the eye midpoint in eye distances, raw image x (positive = toward image right).
    var proxyX: Double
    /// Nose height relative to the midpoint of eyes and mouth, in eye distances (positive = nose higher).
    var proxyY: Double
    /// Vision's face box, normalized, bottom-left origin.
    var box: CGRect
    /// Face box width as a fraction of the frame width.
    var boxWidth: Double { Double(box.width) }
    /// The narrowest face (as a fraction of the frame's width) that counts as a face at all, in scanning, enrolment
    /// and the test. 1.7.1: 0.14 at 640x480; the 16:9 frames of `FaceCamera` show more to the sides, so the same
    /// distance is a narrower share of the frame.
    static let minimumWidth = 0.11
    /// Eyes, nose, mouth corners in image coordinates (bottom-left origin), ordered left to right.
    var points: [CGPoint]
    /// Eye height over eye width along the eye axis, both eyes averaged. Drops sharply during a blink.
    var eyeOpenness: Double
    /// Mouth corner to corner, in eye distances. Widens with a smile.
    var mouthWidth: Double
    /// The face sits inside a rectangle that hugs it: the edge of a held-up photo, phone or tablet.
    var framed: Bool
    /// The rectangle `framed` found (normalized, bottom-left origin) and Vision's confidence in it, for the log.
    var framedBy: (rect: CGRect, confidence: Float)?
    var pixelBuffer: CVPixelBuffer

    /// The 112x112 ArcFace-aligned crop, rendered on demand.
    func alignedImage() -> CGImage? { FaceAligner.render(pixelBuffer, points: points) }
}

/// Finds the largest face and its five alignment points with Vision.
final class FaceAnalyzer: @unchecked Sendable {
    /// The photo-edge check only counts how many of the last ten frames had a rectangle round the face, so the
    /// rectangle search (the dearer of the two requests) runs on a third of the frames with a face and on none
    /// without one; the frames between reuse the last rectangles, compared with their own face box.
    private static let rectEvery = 3
    private let lock = NSLock()
    private var cachedRects: [(box: CGRect, confidence: Float)] = []
    private var sinceRects = 0

    func analyze(_ pb: CVPixelBuffer) -> FaceAnalysis? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pb)
        guard (try? handler.perform([request])) != nil,
              let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let lm = face.landmarks else {
            lock.lock(); cachedRects = []; sinceRects = 0; lock.unlock()
            return nil
        }
        lock.lock()
        let refresh = sinceRects % Self.rectEvery == 0
        sinceRects += 1
        lock.unlock()
        if refresh {
            let rects = VNDetectRectanglesRequest()
            rects.minimumSize = 0.15
            rects.maximumObservations = 6
            rects.minimumConfidence = 0.6
            rects.minimumAspectRatio = 0.3
            rects.quadratureTolerance = 25
            let found = (try? handler.perform([rects])) != nil ? (rects.results ?? []).map { ($0.boundingBox, $0.confidence) } : []
            lock.lock(); cachedRects = found; lock.unlock()
        }
        lock.lock(); let rectList = cachedRects; lock.unlock()

        let size = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        func pts(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] { r?.pointsInImage(imageSize: size) ?? [] }
        func centroid(_ p: [CGPoint]) -> CGPoint? {
            guard !p.isEmpty else { return nil }
            return CGPoint(x: p.map(\.x).reduce(0, +) / Double(p.count), y: p.map(\.y).reduce(0, +) / Double(p.count))
        }
        guard let e1 = centroid(pts(lm.leftPupil)) ?? centroid(pts(lm.leftEye)),
              let e2 = centroid(pts(lm.rightPupil)) ?? centroid(pts(lm.rightEye)),
              let nose = centroid(pts(lm.nose)) else { return nil }
        let lips = pts(lm.outerLips)
        guard let m1 = lips.min(by: { $0.x < $1.x }), let m2 = lips.max(by: { $0.x < $1.x }) else { return nil }

        let (eL, eR) = e1.x <= e2.x ? (e1, e2) : (e2, e1)
        let eyeDist = hypot(eR.x - eL.x, eR.y - eL.y)
        guard eyeDist > 8 else { return nil }
        let eyeMid = CGPoint(x: (eL.x + eR.x) / 2, y: (eL.y + eR.y) / 2)
        let mouthMid = CGPoint(x: (m1.x + m2.x) / 2, y: (m1.y + m2.y) / 2)
        let baseline = (eyeMid.y + mouthMid.y) / 2

        // Eye openness measured along the eye axis, so head roll doesn't change it.
        let ux = (eR.x - eL.x) / eyeDist, uy = (eR.y - eL.y) / eyeDist
        func openness(_ p: [CGPoint]) -> Double? {
            guard p.count >= 4 else { return nil }
            let along = p.map { $0.x * ux + $0.y * uy }, across = p.map { -$0.x * uy + $0.y * ux }
            guard let a0 = along.min(), let a1 = along.max(), let c0 = across.min(), let c1 = across.max(), a1 - a0 > 1 else { return nil }
            return Double((c1 - c0) / (a1 - a0))
        }
        let eyes = [openness(pts(lm.leftEye)), openness(pts(lm.rightEye))].compactMap { $0 }
        let eyeOpenness = eyes.isEmpty ? 0 : eyes.reduce(0, +) / Double(eyes.count)

        let hugging = rectList.first { PhotoCheck.hugs(face.boundingBox, $0.box) }
        let framed = hugging != nil

        return FaceAnalysis(proxyX: Double((nose.x - eyeMid.x) / eyeDist),
                            proxyY: Double((nose.y - baseline) / eyeDist),
                            box: face.boundingBox,
                            points: [eL, eR, nose, m1, m2],
                            eyeOpenness: eyeOpenness,
                            mouthWidth: Double(hypot(m2.x - m1.x, m2.y - m1.y) / eyeDist),
                            framed: framed,
                            framedBy: hugging.map { ($0.box, $0.confidence) },
                            pixelBuffer: pb)
    }
}

/// For tuning the photo-edge check (1.7.1): what rectangle it found round the face, at most twice a second.
enum FramedLog {
    private static let log = Logger(subsystem: "com.marcogad.islet", category: "unlock")
    private static let last = OSAllocatedUnfairLock(initialState: Date.distantPast)

    static func note(_ a: FaceAnalysis, source: String) {
        guard let by = a.framedBy else { return }
        let now = Date()
        let go = last.withLock { t in
            guard now.timeIntervalSince(t) >= 0.5 else { return false }
            t = now
            return true
        }
        guard go else { return }
        let r = by.rect, f = a.box
        let w = CVPixelBufferGetWidth(a.pixelBuffer), h = CVPixelBufferGetHeight(a.pixelBuffer)
        log.debug("photo edge (\(source, privacy: .public)): frame \(w)x\(h) rect x \(r.minX, format: .fixed(precision: 2)) y \(r.minY, format: .fixed(precision: 2)) w \(r.width, format: .fixed(precision: 2)) h \(r.height, format: .fixed(precision: 2)) conf \(by.confidence, format: .fixed(precision: 2)) face w \(f.width, format: .fixed(precision: 2)) h \(f.height, format: .fixed(precision: 2)) face/rect w \(f.width / r.width, format: .fixed(precision: 2)) h \(f.height / r.height, format: .fixed(precision: 2))")
    }
}

/// Anti-spoofing signals that work with a plain 2D webcam. Neither is proof on its own; together they stop the easy
/// attacks (a printed photo, a picture on a phone or tablet).
enum PhotoCheck {
    /// True when `rect` (a straight-edged quad Vision found) encloses the face snugly: a photo print or a screen
    /// held up to the camera. A real head in front of a picture frame or monitor usually hides the rectangle's bottom
    /// edge behind the neck and shoulders, so Vision doesn't see a closed quad there. Normalized coordinates.
    static func hugs(_ face: CGRect, _ rect: CGRect) -> Bool {
        guard rect.width < 0.95 || rect.height < 0.95 else { return false } // the whole frame isn't a photo edge
        guard rect.insetBy(dx: -0.02, dy: -0.02).contains(face) else { return false }
        // The face is some of the picture, not nearly all of it: a photo or screen shows the head with room above
        // and below (the face box was at most half the rectangle's height). Without this, the owner's own head, hair
        // and beard made a tall rectangle that hugged the face, and real scans were refused as "photo edge"
        // (1.7.1 log: face 0.27 of a rectangle 0.42 high, confidence 1.00, with the spoof model at Real 1.00).
        return face.width / rect.width >= 0.25 && face.height / rect.height >= 0.18 && face.height / rect.height <= 0.5
    }
}

/// A blink is the eyes closing well below their open level, then opening again. A printed photo can't do it;
/// a video on a phone can, which is what the rectangle check above is for.
struct BlinkDetector {
    private var peak = 0.0
    private var frames = 0
    private var closed = false
    private(set) var blinked = false

    mutating func reset() { self = BlinkDetector() }

    mutating func add(_ openness: Double) {
        guard openness > 0 else { return }
        frames += 1
        // The open level follows the largest recent value and decays slowly, so a squint or a head turn
        // doesn't leave it stuck high.
        peak = max(openness, peak * 0.985)
        guard frames >= 4 else { return }
        if openness < peak * 0.6 { closed = true } else if closed && openness > peak * 0.82 { blinked = true; closed = false }
    }
}

/// What a scan can ask the face to do to show it is live. A photo can't do any of them; a video could only by
/// chance, since the request is picked at random for each attempt.
enum LivenessChallenge: CaseIterable, Sendable {
    case blink, smile, turnLeft, turnRight

    var prompt: String {
        switch self {
        case .blink: "Blink to unlock"
        case .smile: "Smile to unlock"
        case .turnLeft: "Turn your head left"
        case .turnRight: "Turn your head right"
        }
    }
}

/// How hard face unlock checks that the face is live (Settings > Face Unlock > Security; owner's design,
/// 2026-11-23). Each level tries the quiet checks first and goes further only when it isn't sure:
/// 1. the spoof model, over the last `spoofFrames` frames: at or above `liveLevel` it unlocks at once;
/// 2. the glow (`usesGlow`): the screen lights the face and its shape has to answer, with the spoof model at least at
///    `glowSpoofFloor`;
/// 3. a challenge, the last resort: a blink, or with `randomChallenge` a blink, smile or head turn.
/// Below `refuseLevel` (over `SpoofTracker.refuseFrames`) Faster refuses the face outright, like a held-up photo's edge;
/// Standard and More secure doubt it, and then need the glow and the challenge both (ScanEngine). The level also sets how
/// close to you a face has to be (`matchFloor`, and how tightly the learned threshold follows your scores).
enum FaceSecurity: String, CaseIterable, Sendable {
    /// Trusts the spoof model sooner and never lights the screen: a good video on a phone could get through.
    case faster
    case standard
    /// Lights the screen unless the spoof model is very sure, and asks for a random challenge last.
    case secure

    var liveLevel: Float {
        switch self { case .faster: 0.75; case .standard: 0.90; case .secure: 0.97 }
    }
    /// Spoof model frames averaged for `liveLevel` (the camera runs at ~30 fps).
    var spoofFrames: Int {
        switch self { case .faster: 6; case .standard: 12; case .secure: 20 }
    }
    var refuseLevel: Float { self == .secure ? 0.35 : 0.25 }
    var usesGlow: Bool { self != .faster }
    /// After the glow vouches, the spoof model still has to lean this way.
    var glowSpoofFloor: Float { self == .secure ? 0.75 : 0.5 }
    var randomChallenge: Bool { self == .secure }

    /// The match threshold (similarity to your enrolled looks) until 20 unlocks are learned, and its floor after.
    var matchFloor: Float {
        switch self { case .faster: 0.45; case .standard: 0.50; case .secure: 0.55 }
    }
    /// Once learned, how far under your usual scores (their 5th percentile) the threshold sits.
    var matchMargin: Float {
        switch self { case .faster: 0.08; case .standard: 0.05; case .secure: 0.02 }
    }
    /// The most it can rise above `matchFloor`. Faster and Standard stop at 0.55 and 0.60, 1.5's ceiling: higher, a
    /// new look (glasses, a hood, other light) fails before it can be learned, and it adds nothing against a photo
    /// of you, which the liveness checks stop, not the match (RESEARCH.md, 2026-11-24).
    var matchMaxRaise: Float {
        switch self { case .faster: 0.10; case .standard: 0.10; case .secure: 0.25 }
    }

    var title: String {
        switch self { case .faster: "Faster"; case .standard: "Standard"; case .secure: "More secure" }
    }
    var summary: String {
        switch self {
        case .faster:
            "Unlocks as soon as the spoof model is fairly sure your face is real, and asks for a blink when it isn't. The screen never lights up, and the match is the most forgiving. A good video of you on a phone could get through."
        case .standard:
            "Unlocks at once when the spoof model is sure. When it isn't, the screen glows briefly to check your face's shape, and a blink is the last resort. When it thinks your face is fake (a hood can do that), it needs the glow and the blink both."
        case .secure:
            "Unlocks at once only when the spoof model is very sure. Otherwise the screen glows to check your face's shape, and a random blink, smile or head turn is the last resort. Your face has to match your usual scores closely. Slower, and the glow shows more often."
        }
    }
}

/// Watches the frames for one challenge. Each measure is compared with the face's own resting level in this scan,
/// so it works whatever the face's proportions.
struct ChallengeDetector {
    let challenge: LivenessChallenge
    private var blink = BlinkDetector()
    /// Resting mouth width: follows the narrowest recent value, rising slowly.
    private var restingMouth = 0.0
    /// Resting head turn: the average of the first frames.
    private var restingYaw: [Double] = []
    private var frames = 0
    private var streak = 0
    private(set) var done = false

    /// Mouth wider than this times its resting width is a smile.
    static let smileRatio = 1.12
    /// Nose moved sideways this far (eye distances) from where it rested is a head turn.
    static let turn = 0.18

    init(_ challenge: LivenessChallenge) { self.challenge = challenge }

    mutating func reset() { self = ChallengeDetector(challenge) }

    /// `yaw` is FaceAnalysis.proxyX: raw camera x, so turning to your left makes it larger.
    mutating func add(openness: Double, mouth: Double, yaw: Double) {
        guard !done else { return }
        frames += 1
        switch challenge {
        case .blink:
            blink.add(openness)
            done = blink.blinked
        case .smile:
            guard mouth > 0 else { return }
            restingMouth = restingMouth == 0 ? mouth : min(mouth, restingMouth * 1.003)
            guard frames >= 4 else { return }
            streak = mouth > restingMouth * Self.smileRatio ? streak + 1 : 0
            done = streak >= 2
        case .turnLeft, .turnRight:
            if restingYaw.count < 3 { restingYaw.append(yaw); return }
            let rest = restingYaw.reduce(0, +) / Double(restingYaw.count)
            let moved = (yaw - rest) * (challenge == .turnLeft ? 1 : -1)
            streak = moved > Self.turn ? streak + 1 : 0
            done = streak >= 2
        }
    }
}

/// Mean brightness of a BGRA frame, 0...1, from a sparse grid of pixels.
enum FrameLight {
    static func luma(_ pb: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0, n = 0.0
        for y in stride(from: h / 24, to: h, by: max(h / 12, 1)) {
            for x in stride(from: w / 32, to: w, by: max(w / 16, 1)) {
                let o = y * row + x * 4
                sum += 0.114 * Double(p[o]) + 0.587 * Double(p[o + 1]) + 0.299 * Double(p[o + 2])
                n += 1
            }
        }
        return n > 0 ? sum / n / 255 : nil
    }
}

/// Maps a face onto the 112x112 ArcFace template with a similarity transform.
enum FaceAligner {
    static let size: CGFloat = 112
    /// InsightFace template (top-left origin), flipped to Core Image's bottom-left origin.
    static let template: [CGPoint] = [
        (38.2946, 51.6963), (73.5318, 51.5014), (56.0252, 71.7366), (41.5493, 92.3655), (70.7299, 92.2041),
    ].map { CGPoint(x: $0.0, y: 112 - $0.1) }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Least-squares rotation + uniform scale + translation taking `src` onto `dst` (Umeyama, no reflection).
    static func transform(from src: [CGPoint], to dst: [CGPoint] = template) -> CGAffineTransform {
        let n = Double(src.count)
        let sx = src.map(\.x).reduce(0, +) / n, sy = src.map(\.y).reduce(0, +) / n
        let dx = dst.map(\.x).reduce(0, +) / n, dy = dst.map(\.y).reduce(0, +) / n
        var numA = 0.0, numB = 0.0, den = 0.0
        for (s, d) in zip(src, dst) {
            let xs = s.x - sx, ys = s.y - sy, xd = d.x - dx, yd = d.y - dy
            numA += xs * xd + ys * yd
            numB += xs * yd - ys * xd
            den += xs * xs + ys * ys
        }
        guard den > 0 else { return .identity }
        let a = numA / den, b = numB / den
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: dx - (a * sx - b * sy), ty: dy - (b * sx + a * sy))
    }

    static func render(_ pb: CVPixelBuffer, points: [CGPoint]) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let image = CIImage(cvPixelBuffer: pb).transformed(by: transform(from: points)).cropped(to: rect)
        return context.createCGImage(image, from: rect)
    }
}
