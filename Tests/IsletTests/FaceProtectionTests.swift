import XCTest
@testable import Islet

final class FaceProtectionTests: XCTestCase {
    private func unit(_ v: [Float]) -> [Float] {
        let n = v.map { $0 * $0 }.reduce(0, +).squareRoot()
        return v.map { $0 / n }
    }

    func testBlinkNeedsCloseThenOpen() {
        var b = BlinkDetector()
        for _ in 0..<6 { b.add(0.30) }
        XCTAssertFalse(b.blinked)
        b.add(0.12) // closed
        XCTAssertFalse(b.blinked)
        b.add(0.29) // open again
        XCTAssertTrue(b.blinked)
    }

    func testStillPhotoNeverBlinks() {
        var b = BlinkDetector()
        for i in 0..<60 { b.add(0.30 + Double(i % 3) * 0.01) } // sensor noise only
        XCTAssertFalse(b.blinked)
    }

    func testSmileNeedsAWiderMouth() {
        var d = ChallengeDetector(.smile)
        for _ in 0..<10 { d.add(openness: 0.3, mouth: 1.00 + Double.random(in: -0.02...0.02), yaw: 0) }
        XCTAssertFalse(d.done)
        d.add(openness: 0.3, mouth: 1.2, yaw: 0)
        d.add(openness: 0.3, mouth: 1.22, yaw: 0)
        XCTAssertTrue(d.done)
    }

    func testTurnMustGoTheAskedWay() {
        var left = ChallengeDetector(.turnLeft), right = ChallengeDetector(.turnRight)
        for _ in 0..<3 { left.add(openness: 0.3, mouth: 1, yaw: 0.05); right.add(openness: 0.3, mouth: 1, yaw: 0.05) }
        for _ in 0..<3 { left.add(openness: 0.3, mouth: 1, yaw: 0.35); right.add(openness: 0.3, mouth: 1, yaw: 0.35) }
        XCTAssertTrue(left.done)   // raw camera x grows when you turn to your left
        XCTAssertFalse(right.done)
    }

    func testHotspotAddressRange() {
        XCTAssertTrue(WiFiController.isPhoneHotspotAddress("172.20.10.3"))
        XCTAssertFalse(WiFiController.isPhoneHotspotAddress("192.168.1.20"))
    }

    func testHeldPhotoEdgeIsDetected() {
        let face = CGRect(x: 0.40, y: 0.40, width: 0.20, height: 0.25)
        // A phone screen just around the face.
        XCTAssertTrue(PhotoCheck.hugs(face, CGRect(x: 0.33, y: 0.25, width: 0.34, height: 0.55)))
        // A door or wall far bigger than the face: not a photo edge.
        XCTAssertFalse(PhotoCheck.hugs(face, CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)))
        // A rectangle beside the face.
        XCTAssertFalse(PhotoCheck.hugs(face, CGRect(x: 0.65, y: 0.3, width: 0.3, height: 0.4)))
    }

    func testLearningIsAnchoredToEnrolment() {
        let me = [unit([1, 0, 0, 0]), unit([1, 0.1, 0, 0]), unit([1, 0, 0.1, 0])]
        // Clearly me but in new light: kept.
        XCTAssertTrue(FaceLearning.shouldLearn(unit([1, 0.5, 0.4, 0.3]), enrolled: me, learned: [], threshold: 0.45))
        // Almost identical to the enrolment: adds nothing.
        XCTAssertFalse(FaceLearning.shouldLearn(unit([1, 0.02, 0.02, 0]), enrolled: me, learned: [], threshold: 0.45))
        // Close to a learned look but not to the enrolment: never kept, so learning can't drift.
        let drifted = unit([0.4, 0, 0, 1])
        XCTAssertFalse(FaceLearning.shouldLearn(drifted, enrolled: me, learned: [unit([0.5, 0, 0, 1])], threshold: 0.45))
    }
}
