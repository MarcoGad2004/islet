import CoreImage
import Vision

/// What we learn about a face in one frame.
struct FaceAnalysis: @unchecked Sendable {
    /// Nose offset from the eye midpoint in eye distances, raw image x (positive = toward image right).
    var proxyX: Double
    /// Nose height relative to the midpoint of eyes and mouth, in eye distances (positive = nose higher).
    var proxyY: Double
    /// Face box width as a fraction of the frame width.
    var boxWidth: Double
    /// Eyes, nose, mouth corners in image coordinates (bottom-left origin), ordered left to right.
    var points: [CGPoint]
    var pixelBuffer: CVPixelBuffer

    /// The 112x112 ArcFace-aligned crop, rendered on demand.
    func alignedImage() -> CGImage? { FaceAligner.render(pixelBuffer, points: points) }
}

/// Finds the largest face and its five alignment points with Vision.
struct FaceAnalyzer: Sendable {
    func analyze(_ pb: CVPixelBuffer) -> FaceAnalysis? {
        let request = VNDetectFaceLandmarksRequest()
        guard (try? VNImageRequestHandler(cvPixelBuffer: pb).perform([request])) != nil,
              let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let lm = face.landmarks else { return nil }

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

        return FaceAnalysis(proxyX: Double((nose.x - eyeMid.x) / eyeDist),
                            proxyY: Double((nose.y - baseline) / eyeDist),
                            boxWidth: Double(face.boundingBox.width),
                            points: [eL, eR, nose, m1, m2],
                            pixelBuffer: pb)
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
