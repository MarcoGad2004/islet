import XCTest
@testable import Islet

final class FrameDurationClampTests: XCTestCase {
    /// A typical built-in camera: 15 to 30 frames a second.
    private let ranges = [(min: 1.0 / 30, max: 1.0 / 15)]

    func testFiveFpsIsMovedToTheSlowestTheCameraCan() {
        // The 5 fps cap used while the camera warms up: 0.2 s is outside 1/30...1/15 and made the camera throw.
        XCTAssertEqual(FaceCamera.clampedFrameDuration(0.2, ranges: ranges)!, 1.0 / 15, accuracy: 1e-9)
    }
    func testASupportedDurationIsKept() {
        XCTAssertEqual(FaceCamera.clampedFrameDuration(1.0 / 20, ranges: ranges)!, 1.0 / 20, accuracy: 1e-9)
    }
    func testTooFastIsMovedToTheFastest() {
        XCTAssertEqual(FaceCamera.clampedFrameDuration(1.0 / 120, ranges: ranges)!, 1.0 / 30, accuracy: 1e-9)
    }
    func testNoRangesMeansNothingToSet() {
        XCTAssertNil(FaceCamera.clampedFrameDuration(0.2, ranges: []))
    }
}
