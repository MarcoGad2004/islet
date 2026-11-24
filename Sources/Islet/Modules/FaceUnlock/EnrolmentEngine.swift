import CoreGraphics
import Foundation

/// Live state of an enrolment, published to the UI.
struct EnrolmentSnapshot: Sendable {
    var faceVisible = false
    /// Head position in the ring, mirror-style: x right, y up. Length 1 touches the ring.
    var x = 0.0, y = 0.0
    var filled = [Bool](repeating: false, count: EnrolmentEngine.sectorCount)
    var calibrated = false
    /// The direction to do next (a sector), nil once all are done.
    var target: Int? = EnrolmentEngine.order.first
    var progress: Double { Double(filled.filter { $0 }.count) / Double(filled.count) }
}

/// Guides the user through four head moves and collects face embeddings on the way: a few looking straight ahead
/// (which also calibrates "straight ahead"), then three each tilting up, down, left and right, one at a time (owner,
/// 2026-11-24; it was a full circle of eight directions, which the model doesn't need: it sees one photo at a time,
/// and a scan compares with the closest three).
/// Runs on the camera queue; state is guarded by a lock.
final class EnrolmentEngine: @unchecked Sendable {
    /// Sectors run counter-clockwise from the right, mirror-style: 0 right, 1 up, 2 left, 3 down.
    static let sectorCount = 4
    /// The order they're asked for: up, down, left, right.
    static let order = [1, 3, 2, 0]
    /// Head movement (in eye distances) that counts as reaching the ring. Tune on the real camera.
    static let reachX = 0.10, reachY = 0.075
    private static let samplesPerSector = 3, centreSamples = 3, calibrationFrames = 9

    private let embedder: FaceEmbedder
    private let onUpdate: @Sendable (EnrolmentSnapshot) -> Void
    private let onFinish: @Sendable ([[Float]]) -> Void
    private let lock = NSLock()

    private var snapshot = EnrolmentSnapshot()
    private var samples: [[Float]] = []
    private var counts = [Int](repeating: 0, count: sectorCount)
    private var calibration: [(Double, Double)] = []
    private var neutral = (x: 0.0, y: 0.0)
    private var lastCapture = Date.distantPast
    private var smoothed = (x: 0.0, y: 0.0)
    private var finished = false

    init(embedder: FaceEmbedder, onUpdate: @escaping @Sendable (EnrolmentSnapshot) -> Void,
         onFinish: @escaping @Sendable ([[Float]]) -> Void) {
        self.embedder = embedder
        self.onUpdate = onUpdate
        self.onFinish = onFinish
    }

    func handle(_ analysis: FaceAnalysis?) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        guard let a = analysis, a.boxWidth > FaceAnalysis.minimumWidth else {
            snapshot.faceVisible = false
            calibration.removeAll()
            onUpdate(snapshot)
            return
        }
        snapshot.faceVisible = true

        if !snapshot.calibrated {
            calibration.append((a.proxyX, a.proxyY))
            // Take the first few embeddings while the user looks straight ahead.
            if [3, 6, 9].contains(calibration.count), let e = a.alignedImage().flatMap(embedder.embed) { samples.append(e) }
            if calibration.count >= Self.calibrationFrames {
                neutral = (calibration.map(\.0).reduce(0, +) / Double(calibration.count),
                           calibration.map(\.1).reduce(0, +) / Double(calibration.count))
                snapshot.calibrated = true
            }
            onUpdate(snapshot)
            return
        }

        // The preview is mirrored, so turning to your right moves the dot right (raw image x is flipped).
        let nx = -(a.proxyX - neutral.x) / Self.reachX
        let ny = (a.proxyY - neutral.y) / Self.reachY
        smoothed = (smoothed.x * 0.55 + nx * 0.45, smoothed.y * 0.55 + ny * 0.45)
        snapshot.x = smoothed.x
        snapshot.y = smoothed.y

        let magnitude = hypot(smoothed.x, smoothed.y)
        if magnitude >= 1 {
            var angle = atan2(smoothed.y, smoothed.x)
            if angle < 0 { angle += 2 * .pi }
            let sector = Int((angle / (2 * .pi / Double(Self.sectorCount))).rounded()) % Self.sectorCount
            if sector == snapshot.target { capture(sector: sector, from: a) }
        }
        onUpdate(snapshot)
    }

    private func capture(sector: Int, from a: FaceAnalysis) {
        guard counts[sector] < Self.samplesPerSector, Date().timeIntervalSince(lastCapture) > 0.3,
              let image = a.alignedImage(), let e = embedder.embed(image) else { return }
        lastCapture = Date()
        samples.append(e)
        counts[sector] += 1
        if counts[sector] >= Self.samplesPerSector {
            snapshot.filled[sector] = true
            snapshot.target = Self.order.first { !snapshot.filled[$0] }
        }
        if snapshot.filled.allSatisfy({ $0 }) {
            finished = true
            onFinish(samples)
        }
    }
}
