import CoreImage
import CoreML

/// A passive spoof check: Minivision's MiniFASNet pair (Apache-2.0, built by scripts/convert-antispoof.py), trained to
/// tell a live face from a print or a screen by its texture (moiré, glare, colour, missing depth blur). It looks at
/// two crops around the face, 2.7x and 4.0x the face box, and gives the probability the face is real. Fast (a few ms).
final class AntiSpoofModel: @unchecked Sendable {
    private let model: MLModel
    private let constraint27: MLImageConstraint, constraint40: MLImageConstraint
    private let lock = NSLock()
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    static let side: CGFloat = 80

    /// nil when the model isn't in the app bundle.
    init?() {
        guard let url = Bundle.main.url(forResource: "AntiSpoof", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url),
              let c27 = model.modelDescription.inputDescriptionsByName["crop27"]?.imageConstraint,
              let c40 = model.modelDescription.inputDescriptionsByName["crop40"]?.imageConstraint else { return nil }
        self.model = model
        constraint27 = c27; constraint40 = c40
    }

    /// Probability (0...1) that the face is real. `box` is Vision's normalized face box (bottom-left origin).
    func live(_ pb: CVPixelBuffer, face box: CGRect) -> Float? {
        let size = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        let image = CIImage(cvPixelBuffer: pb)
        guard let a = Self.crop(image, size: size, box: box, scale: 2.7),
              let b = Self.crop(image, size: size, box: box, scale: 4.0) else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let va = try? MLFeatureValue(cgImage: a, constraint: constraint27),
              let vb = try? MLFeatureValue(cgImage: b, constraint: constraint40),
              let input = try? MLDictionaryFeatureProvider(dictionary: ["crop27": va, "crop40": vb]),
              let out = try? model.prediction(from: input),
              let live = out.featureValue(for: "live")?.multiArrayValue, live.count > 0 else { return nil }
        return live[0].floatValue
    }

    private static func crop(_ image: CIImage, size: CGSize, box: CGRect, scale: CGFloat) -> CGImage? {
        // The training code works top-left; Core Image bottom-left. The crop is symmetric about the face centre, so
        // only the final rect needs flipping.
        let face = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        let r = cropBox(image: size, face: face, scale: scale)
        guard r.width > 4, r.height > 4 else { return nil }
        let flipped = CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
        let out = image.cropped(to: flipped)
            .transformed(by: CGAffineTransform(translationX: -flipped.minX, y: -flipped.minY))
            .transformed(by: CGAffineTransform(scaleX: side / flipped.width, y: side / flipped.height))
        return context.createCGImage(out, from: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// The training code's crop (`CropImage._get_new_box`): the face box scaled about its centre, shrunk to fit the
    /// image, then slid back inside it. Top-left origin, pixels.
    static func cropBox(image: CGSize, face: CGRect, scale: CGFloat) -> CGRect {
        let w = image.width, h = image.height
        let s = min((h - 1) / face.height, min((w - 1) / face.width, scale))
        let nw = face.width * s, nh = face.height * s
        var x0 = face.midX - nw / 2, y0 = face.midY - nh / 2, x1 = face.midX + nw / 2, y1 = face.midY + nh / 2
        if x0 < 0 { x1 -= x0; x0 = 0 }
        if y0 < 0 { y1 -= y0; y0 = 0 }
        if x1 > w - 1 { x0 -= x1 - w + 1; x1 = w - 1 }
        if y1 > h - 1 { y0 -= y1 - h + 1; y1 = h - 1 }
        return CGRect(x: x0.rounded(.down), y: y0.rounded(.down), width: (x1 - x0).rounded(.down), height: (y1 - y0).rounded(.down))
    }
}

/// The spoof model's view of one scan: the mean of its recent frames.
struct SpoofTracker {
    enum Verdict: Equatable { case unknown, live, unsure, spoof }
    /// Mean at or above this vouches for the face (with the pulse, it lets Automatic skip the challenge).
    static let liveLevel: Float = 0.75
    /// Mean below this over enough frames refuses the face, like a photo edge.
    static let spoofLevel: Float = 0.25
    static let window = 12

    private(set) var values: [Float] = []
    mutating func add(_ v: Float) { values.append(v); if values.count > Self.window { values.removeFirst() } }
    mutating func reset() { values = [] }
    var mean: Float? { values.isEmpty ? nil : values.reduce(0, +) / Float(values.count) }
    var verdict: Verdict {
        guard let mean, values.count >= 4 else { return .unknown }
        if mean >= Self.liveLevel { return .live }
        if values.count >= 6, mean < Self.spoofLevel { return .spoof }
        return .unsure
    }
}
