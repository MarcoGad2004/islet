import Accelerate
import CoreML

/// Turns an aligned 112x112 face into a 512-number identity vector (AuraFace / ArcFace-style, L2-normalised).
final class FaceEmbedder: @unchecked Sendable {
    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let constraint: MLImageConstraint
    private let lock = NSLock()

    /// nil when the model isn't in the app bundle (run scripts/fetch-model.sh, then xcodegen generate).
    init?() {
        guard let url = Bundle.main.url(forResource: "FaceEmbedding", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url),
              let input = model.modelDescription.inputDescriptionsByName.first(where: { $0.value.imageConstraint != nil }),
              let output = model.modelDescription.outputDescriptionsByName.keys.first,
              let constraint = input.value.imageConstraint else { return nil }
        self.model = model
        inputName = input.key
        outputName = output
        self.constraint = constraint
    }

    func embed(_ image: CGImage) -> [Float]? {
        lock.lock(); defer { lock.unlock() }
        guard let value = try? MLFeatureValue(cgImage: image, constraint: constraint),
              let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: value]),
              let out = try? model.prediction(from: provider),
              let array = out.featureValue(for: outputName)?.multiArrayValue else { return nil }
        var v = (0..<array.count).map { array[$0].floatValue }
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = norm.squareRoot()
        guard norm > 0 else { return nil }
        v = v.map { $0 / norm }
        return v
    }
}

enum FaceMatcher {
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var d: Float = 0
        vDSP_dotpr(a, 1, b, 1, &d, vDSP_Length(min(a.count, b.count)))
        return d // both are unit length
    }

    /// Mean of the best three similarities to the enrolled faces.
    static func score(_ probe: [Float], enrolled: [[Float]]) -> Float {
        let top = enrolled.map { cosine(probe, $0) }.sorted(by: >).prefix(3)
        return top.isEmpty ? 0 : top.reduce(0, +) / Float(top.count)
    }

    /// Mean similarity of each sample to the average face: a rough check that an enrolment is consistent.
    static func consistency(_ samples: [[Float]]) -> Float {
        guard let first = samples.first else { return 0 }
        var mean = [Float](repeating: 0, count: first.count)
        for s in samples { for i in mean.indices { mean[i] += s[i] } }
        let norm = mean.map { $0 * $0 }.reduce(0, +).squareRoot()
        guard norm > 0 else { return 0 }
        mean = mean.map { $0 / norm }
        return samples.map { cosine($0, mean) }.reduce(0, +) / Float(samples.count)
    }
}
