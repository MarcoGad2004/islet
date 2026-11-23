import CoreImage
import XCTest
@testable import Islet

/// The screen-light pulse, the spoof model's crop and tracker, and the adaptive threshold.
final class FaceLivenessTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)
    private var schedule: FacePulse.Schedule { FacePulse.Schedule(start: start, brighter: true) }

    /// Frames before and at the peak of a pulse. `gain` gives each patch's brightness multiplier at the peak.
    private func frames(base: [Double] = Array(repeating: 0.2, count: 7), gain: (FacePulse.Patch) -> Double,
                        background: Double = 1.0, matched: Bool = true) -> [FacePulse.Frame] {
        let baseTimes = stride(from: -0.28, through: 0, by: 0.033).map { start.addingTimeInterval($0) }
        let peakTimes = stride(from: FacePulse.rise + 0.1, through: FacePulse.rise + FacePulse.hold, by: 0.033).map { start.addingTimeInterval($0) }
        let b = baseTimes.map { FacePulse.Frame(time: $0, face: base, background: 0.1, matched: matched) }
        let p = peakTimes.map { t in
            FacePulse.Frame(time: t, face: FacePulse.Patch.allCases.map { base[$0.rawValue] * gain($0) }, background: 0.1 * background, matched: matched)
        }
        return b + p
    }

    /// A real head: the face brightens much more than the background, its centre more than its sides.
    private func realGain(_ p: FacePulse.Patch) -> Double {
        switch p {
        case .forehead, .nose, .chin: 1.20
        case .leftCheek, .rightCheek: 1.15
        case .leftSide, .rightSide: 1.09
        }
    }

    func testRealFacePasses() {
        let v = FacePulse.judge(frames(gain: realGain), schedule: schedule, exposureHeld: true, learned: [])
        XCTAssertTrue(v.passed, "\(v)")
        XCTAssertEqual(v.reading?.contrast ?? 0, 0.2, accuracy: 0.01)
        XCTAssertGreaterThan(v.reading?.shape ?? 0, FacePulse.minShape)
    }

    func testPrintedPhotoIsFlat() {
        // A print near the screen brightens like a face, but every part of it alike.
        let v = FacePulse.judge(frames(gain: { _ in 1.2 }), schedule: schedule, exposureHeld: true, learned: [])
        XCTAssertEqual(v.reason, "flat")
    }

    func testScreenDoesNotRespond() {
        // A phone makes its own light: hardly any change.
        let v = FacePulse.judge(frames(gain: { _ in 1.01 }), schedule: schedule, exposureHeld: true, learned: [])
        XCTAssertEqual(v.reason, "no response to the light")
    }

    func testExposureChangeCancelsOut() {
        // Auto-exposure darkened everything by 20%: the background shows it, and the face still passes.
        let v = FacePulse.judge(frames(gain: { self.realGain($0) * 0.8 }, background: 0.8), schedule: schedule,
                                exposureHeld: false, learned: [])
        XCTAssertTrue(v.passed, "\(v)")
        // Without a background or a held exposure there's nothing to compare with.
        let none = frames(gain: realGain).map { f -> FacePulse.Frame in var f = f; f.background = nil; return f }
        XCTAssertEqual(FacePulse.judge(none, schedule: schedule, exposureHeld: false, learned: []).reason, "no background")
    }

    func testSwappedFaceIsNotVouchedFor() {
        let v = FacePulse.judge(frames(gain: realGain, matched: false), schedule: schedule, exposureHeld: true, learned: [])
        XCTAssertEqual(v.reason, "face changed")
    }

    func testLearnedPatternMustAgree() {
        let mine = FacePulse.judge(frames(gain: realGain), schedule: schedule, exposureHeld: true, learned: []).reading!.profile!
        let learned = Array(repeating: mine, count: FacePulse.profileMinimum)
        XCTAssertTrue(FacePulse.judge(frames(gain: realGain), schedule: schedule, exposureHeld: true, learned: learned).passed)
        // A differently shaped face (or mask): the cheeks change most, the forehead least.
        let other: (FacePulse.Patch) -> Double = { p in
            switch p {
            case .forehead: 1.12
            case .nose, .chin: 1.2
            case .leftCheek, .rightCheek: 1.25
            case .leftSide, .rightSide: 1.05
            }
        }
        let v = FacePulse.judge(frames(gain: other), schedule: schedule, exposureHeld: true, learned: learned)
        XCTAssertEqual(v.reason, "not your usual shape")
        // Your own face turned a little: one side lit more than the other, still your pattern.
        let turned: (FacePulse.Patch) -> Double = { p in
            switch p {
            case .forehead, .nose, .chin: 1.20
            case .leftCheek: 1.17
            case .rightCheek: 1.13
            case .leftSide: 1.12
            case .rightSide: 1.06
            }
        }
        XCTAssertTrue(FacePulse.judge(frames(gain: turned), schedule: schedule, exposureHeld: true, learned: learned).passed)
    }

    func testDimmingPulseWorksToo() {
        let s = FacePulse.Schedule(start: start, brighter: false)
        let v = FacePulse.judge(frames(gain: { 2 - self.realGain($0) }), schedule: s, exposureHeld: true, learned: [])
        XCTAssertTrue(v.passed, "\(v)")
    }

    func testTooFewFrames() {
        XCTAssertEqual(FacePulse.judge([], schedule: schedule, exposureHeld: true, learned: []).reason, "too few frames")
    }

    // MARK: Harsh light

    /// A 640x480 frame lit `left` on the image's left half and `right` on its right half (gamma values 0...1).
    private func frame(left: Double, right: Double) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32BGRA, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self), row = CVPixelBufferGetBytesPerRow(pb!)
        for y in 0..<480 {
            for x in 0..<640 {
                let v = UInt8(((x < 320 ? left : right) * 255).rounded())
                let o = y * row + x * 4
                base[o] = v; base[o + 1] = v; base[o + 2] = v; base[o + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
    }

    /// A face centred in the frame: eyes 80 px apart.
    private let facePoints = [CGPoint(x: 280, y: 280), CGPoint(x: 360, y: 280), CGPoint(x: 320, y: 240), CGPoint(x: 290, y: 190), CGPoint(x: 350, y: 190)]
    private let faceBox = CGRect(x: 0.36, y: 0.3, width: 0.28, height: 0.45)

    func testEvenLightIsNotHarsh() {
        let l = FacePulse.lighting(frame(left: 0.55, right: 0.5), points: facePoints, face: faceBox)!
        XCTAssertFalse(l.harsh)
        XCTAssertEqual(l.clipped, 0)
    }

    func testSunOnOneSideIsHarsh() {
        // Sun from the left: that side bright, the other in shadow (linear ratio ~4.5).
        let l = FacePulse.lighting(frame(left: 0.85, right: 0.43), points: facePoints, face: faceBox)!
        XCTAssertGreaterThan(l.sideRatio, FacePulse.Lighting.harshSideRatio)
        XCTAssertTrue(l.harsh)
    }

    func testBlownOutFaceIsHarsh() {
        let l = FacePulse.lighting(frame(left: 1.0, right: 1.0), points: facePoints, face: faceBox)!
        XCTAssertEqual(l.clipped, 1)
        XCTAssertTrue(l.harsh)
    }

    // MARK: Spoof model

    func testCropMatchesTrainingCode() {
        // A 100x120 face in a 640x480 frame: 2.7x is 270x324, centred on the face.
        let crop = AntiSpoofModel.cropBox(image: CGSize(width: 640, height: 480), face: CGRect(x: 270, y: 180, width: 100, height: 120), scale: 2.7)
        XCTAssertEqual(crop, CGRect(x: 185, y: 78, width: 270, height: 324))
        // 4.0x doesn't fit the height: the scale shrinks to (480-1)/120 and the box slides back inside.
        let big = AntiSpoofModel.cropBox(image: CGSize(width: 640, height: 480), face: CGRect(x: 270, y: 180, width: 100, height: 120), scale: 4)
        XCTAssertEqual(big.minY, 0)
        XCTAssertLessThanOrEqual(big.maxY, 479)
        XCTAssertEqual(big.width, 399, accuracy: 1)
    }

    func testSpoofTrackerNeedsAFewFrames() {
        var t = SpoofTracker()
        for _ in 0..<3 { t.add(0.05) }
        XCTAssertEqual(t.verdict, .unknown)
        t.add(0.05)
        XCTAssertEqual(t.verdict, .unsure) // fake-looking, but not yet enough frames to refuse
        for _ in 0..<2 { t.add(0.05) }
        XCTAssertEqual(t.verdict, .spoof)
        t.reset()
        for _ in 0..<5 { t.add(0.95) }
        XCTAssertEqual(t.verdict, .live)
    }

    /// The real model on Minivision's sample photos (set ISLET_FAS_SAMPLES to the repo's images/sample folder).
    func testModelOnSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["ISLET_FAS_SAMPLES"] else { throw XCTSkip("ISLET_FAS_SAMPLES not set") }
        let model = try XCTUnwrap(AntiSpoofModel(), "AntiSpoof model not in the app bundle")
        for (name, real) in [("image_F1.jpg", false), ("image_F2.jpg", false), ("image_T1.jpg", true)] {
            let image = try XCTUnwrap(CIImage(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(name)))
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
            CIContext().render(image, to: pb!)
            let a = try XCTUnwrap(FaceAnalyzer().analyze(pb!), name)
            let live = try XCTUnwrap(model.live(pb!, face: a.box))
            print("\(name) live=\(live)")
            if real { XCTAssertGreaterThan(live, 0.5, name) } else { XCTAssertLessThan(live, 0.5, name) }
        }
    }

    // MARK: Adaptive threshold

    func testAdaptiveThresholdWaitsForEnoughUnlocks() {
        XCTAssertEqual(AdaptiveThreshold.value(floor: 0.45, scores: Array(repeating: 0.8, count: 19)), 0.45)
    }

    func testAdaptiveThresholdSitsUnderYourScores() {
        let scores = (0..<40).map { 0.6 + Float($0) * 0.005 } // 0.60 ... 0.795
        let t = AdaptiveThreshold.value(floor: 0.45, scores: scores)
        XCTAssertEqual(t, 0.55 + 0.005, accuracy: 0.006) // 5th percentile (~0.61) less 0.05
    }

    func testAdaptiveThresholdIsBounded() {
        // Very high scores: capped at floor + maxRaise.
        XCTAssertEqual(AdaptiveThreshold.value(floor: 0.45, scores: Array(repeating: 0.95, count: 30)), 0.60, accuracy: 0.001)
        // Low scores: never below the floor.
        XCTAssertEqual(AdaptiveThreshold.value(floor: 0.45, scores: Array(repeating: 0.40, count: 30)), 0.45)
    }
}
