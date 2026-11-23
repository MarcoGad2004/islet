import CoreImage
import XCTest
@testable import Islet

/// The screen-light pulse, the spoof model's crop and tracker, and the adaptive threshold.
final class FaceLivenessTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)
    private var schedule: FacePulse.Schedule { FacePulse.Schedule.swell(start: start, brighter: true) }

    /// Frames before and at the peak of a pulse. `gain` gives each patch's brightness multiplier at the peak.
    private func frames(base: [Double] = Array(repeating: 0.2, count: 7), gain: (FacePulse.Patch) -> Double,
                        background: Double = 1.0, matched: Bool = true) -> [FacePulse.Frame] {
        let baseTimes = stride(from: -0.28, through: 0, by: 0.033).map { start.addingTimeInterval($0) }
        let peakTimes = stride(from: FacePulse.rise + 0.1, through: FacePulse.rise + FacePulse.hold, by: 0.033).map { start.addingTimeInterval($0) }
        // Three readable background spots and one blown out (nil), as a real room might give.
        let b = baseTimes.map { FacePulse.Frame(time: $0, face: base, background: [0.1, 0.2, nil, 0.05], matched: matched) }
        let p = peakTimes.map { t in
            FacePulse.Frame(time: t, face: FacePulse.Patch.allCases.map { base[$0.rawValue] * gain($0) }, background: [0.1 * background, 0.2 * background, nil, 0.05 * background], matched: matched)
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
        XCTAssertNotNil(v.reading?.shape)
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
    }

    /// The owner's room (2026-11-23): no background spot readable and an exposure the camera can't lock.
    private func noBackground(_ f: [FacePulse.Frame]) -> [FacePulse.Frame] {
        f.map { var f = $0; f.background = Array(repeating: nil, count: 18); return f }
    }

    func testWithoutBackgroundTheFaceShapeDecides() {
        // A real face, even with auto-exposure pulling everything down 15%: the centre still changes more than the sides.
        let real = FacePulse.judge(noBackground(frames(gain: { self.realGain($0) * 0.85 })), schedule: schedule, exposureHeld: false, learned: [])
        XCTAssertTrue(real.passed, "\(real)")
        XCTAssertNil(real.reading?.contrast)
        // A print or a screen changes evenly: refused to vouch, whatever the exposure did.
        XCTAssertEqual(FacePulse.judge(noBackground(frames(gain: { _ in 1.2 })), schedule: schedule, exposureHeld: false, learned: []).reason, "flat")
        XCTAssertEqual(FacePulse.judge(noBackground(frames(gain: { _ in 0.9 })), schedule: schedule, exposureHeld: false, learned: []).reason, "flat")
    }

    func testBackgroundSpotsAvoidTheHead() {
        let box = CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.45)
        let spots = FacePulse.backgroundSpots(face: box)
        XCTAssertEqual(spots.count, 18)
        for case let p? in spots {
            let overHead = p.x > box.minX - box.width * 0.5 && p.x < box.maxX + box.width * 0.5 && p.y < box.maxY + box.height * 0.25
            XCTAssertFalse(overHead, "\(p)")
        }
        XCTAssertGreaterThan(spots.compactMap { $0 }.count, 6)
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
        let s = FacePulse.Schedule.swell(start: start, brighter: false)
        let v = FacePulse.judge(frames(gain: { 2 - self.realGain($0) }), schedule: s, exposureHeld: true, learned: [])
        XCTAssertTrue(v.passed, "\(v)")
    }

    // MARK: Glow

    /// Frames over a whole glow: each patch at `base` while low and `base * gain` while high, one every 1/30 s.
    private func glowFrames(_ glow: FacePulse.Glow, gain: (FacePulse.Patch) -> Double) -> [FacePulse.Frame] {
        let s = glow.schedule(start: start)
        return stride(from: 0, through: glow.total, by: 1.0 / 30).map { t in
            let time = start.addingTimeInterval(t)
            let up = s.inHigh(time)
            return FacePulse.Frame(time: time, face: FacePulse.Patch.allCases.map { 0.2 * (up ? gain($0) : 1) },
                                   background: [0.1, 0.2, nil].map { $0.map { $0 * (up ? 1.01 : 1) } }, matched: true)
        }
    }

    func testGlowJudgedLikeTheSwell() {
        let glow = FacePulse.Glow(share: 0.3, potential: 16, headroom: 5.5, steps: [true, false, true, true])
        let s = glow.schedule(start: start)
        XCTAssertEqual(s.high.count, 3)
        XCTAssertEqual(s.low.count, 2) // the first hold and the step down
        XCTAssertEqual(s.ready, start.addingTimeInterval(glow.length))
        XCTAssertTrue(FacePulse.judge(glowFrames(glow, gain: realGain), schedule: s, exposureHeld: false, learned: []).passed)
        XCTAssertEqual(FacePulse.judge(glowFrames(glow, gain: { _ in 1.2 }), schedule: s, exposureHeld: false, learned: []).reason, "flat")
        XCTAssertEqual(FacePulse.judge(glowFrames(glow, gain: { _ in 1.01 }), schedule: s, exposureHeld: false, learned: []).reason,
                       "no response to the light")
    }

    func testGlowLevels() {
        // XDR at low brightness (SDR white ~100 nits, so the peak is 16x): a middling room asks for ~4.8x.
        let mid = FacePulse.Glow(share: 0.3, potential: 16, headroom: 16)
        XCTAssertEqual(mid.high, 4.8, accuracy: 0.001)
        XCTAssertEqual(mid.low, 1.68, accuracy: 0.001)
        // Only what the panel allows now, keeping the step.
        let clipped = FacePulse.Glow(share: 0.3, potential: 16, headroom: 2)
        XCTAssertEqual(clipped.high, 2)
        XCTAssertGreaterThanOrEqual(clipped.high / clipped.low, FacePulse.glowRatio - 0.001)
        // A dark room: SDR white stepping up 1.6x, no more.
        let dark = FacePulse.Glow(share: FacePulse.glowShare(lux: 5)!, potential: 16, headroom: 16)
        XCTAssertEqual(dark.low, 1)
        XCTAssertEqual(dark.high, FacePulse.glowRatio, accuracy: 0.001)
        // No EDR at all: it still steps, under SDR white.
        let sdr = FacePulse.Glow(share: 0.3, potential: 1, headroom: 1)
        XCTAssertEqual(sdr.high, 1)
        XCTAssertLessThan(sdr.low, 1)
    }

    func testGlowShareFollowsTheRoom() {
        let dim = FacePulse.glowShare(lux: 10)!, office = FacePulse.glowShare(lux: 500)!, window = FacePulse.glowShare(lux: 1200)!
        XCTAssertLessThan(dim, office)
        XCTAssertLessThan(office, window)
        XCTAssertLessThanOrEqual(window, 0.65)
        XCTAssertNil(FacePulse.glowShare(lux: 5000))
        XCTAssertNotNil(FacePulse.glowShare(lux: nil))
    }

    func testGlowEasesAndNeverFlashesFast() {
        let glow = FacePulse.Glow(share: 0.3, potential: 16, headroom: 16, steps: [true, false, true, false])
        XCTAssertEqual(glow.at(0).alpha, 0)
        XCTAssertEqual(glow.at(glow.total).alpha, 0, accuracy: 0.001)
        // No jump between frames at 120 Hz larger than a small part of the step.
        var last = glow.at(0)
        for t in stride(from: 0.0, through: glow.total, by: 1.0 / 120) {
            let now = glow.at(t)
            XCTAssertLessThan(abs(now.value * now.alpha - last.value * last.alpha), (glow.high - glow.low) * 0.12, "t=\(t)")
            last = now
        }
        // At most one change of level per step slot: under three a second.
        XCTAssertLessThan(1 / (FacePulse.glowStep + FacePulse.glowHold), 3)
        for _ in 0..<50 {
            let s = FacePulse.glowSteps()
            XCTAssertGreaterThanOrEqual(s.filter { $0 }.count, 2)
            XCTAssertTrue(s.contains(false))
        }
    }

    func testTooFewFrames() {
        XCTAssertEqual(FacePulse.judge([], schedule: schedule, exposureHeld: true, learned: []).reason, "too few frames")
    }

    func testChallengeByLevel() {
        for _ in 0..<20 {
            XCTAssertEqual(ScanEngine.pick(.faster), .blink)
            XCTAssertEqual(ScanEngine.pick(.standard), .blink)
        }
        XCTAssertGreaterThan(Set((0..<60).map { _ in ScanEngine.pick(.secure) }).count, 1)
    }

    func testOldModesMoveToTheNearestLevel() {
        XCTAssertEqual(FaceStore.migratedSecurity("automatic"), .standard)
        XCTAssertEqual(FaceStore.migratedSecurity("blink"), .standard)
        XCTAssertEqual(FaceStore.migratedSecurity("random"), .secure)
        XCTAssertEqual(FaceStore.migratedSecurity("off"), .faster)
        XCTAssertEqual(FaceStore.migratedSecurity(nil), .standard)
    }

    func testLevelsGetStricter() {
        let levels = FaceSecurity.allCases
        XCTAssertEqual(levels, [.faster, .standard, .secure])
        for (a, b) in zip(levels, levels.dropFirst()) {
            XCTAssertLessThan(a.liveLevel, b.liveLevel)
            XCTAssertLessThan(a.spoofFrames, b.spoofFrames)
            XCTAssertLessThanOrEqual(a.refuseLevel, b.refuseLevel)
        }
        XCTAssertFalse(FaceSecurity.faster.usesGlow)
        XCTAssertTrue(FaceSecurity.standard.usesGlow && FaceSecurity.secure.usesGlow)
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
        for _ in 0..<5 { t.add(0.05) }
        XCTAssertEqual(t.verdict(.standard), .unknown) // fake-looking, but not yet enough frames to refuse
        t.add(0.05)
        XCTAssertEqual(t.verdict(.standard), .spoof)
        t.reset()
        for _ in 0..<6 { t.add(0.95) }
        XCTAssertEqual(t.verdict(.faster), .live)
        XCTAssertEqual(t.verdict(.standard), .unknown) // Standard looks at 12 frames
        for _ in 0..<6 { t.add(0.95) }
        XCTAssertEqual(t.verdict(.standard), .live)
        XCTAssertEqual(t.verdict(.secure), .unknown)
        for _ in 0..<8 { t.add(0.95) }
        XCTAssertEqual(t.verdict(.secure), .unsure) // 0.95 isn't sure enough for More secure: the glow
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
