import XCTest
@testable import Islet

final class DarkRoomGateTests: XCTestCase {
    func testBrightRoomNeverTriggers() {
        var g = DarkRoomGate()
        for i in 0..<20 { XCTAssertNil(g.feed(luma: 0.5, elapsed: Double(i) * 0.1, settle: 0)) }
        XCTAssertTrue(!g.isDark)
    }

    func testBlackFrameTriggersAtOnce() {
        var g = DarkRoomGate()
        XCTAssertEqual(g.feed(luma: 0.05, elapsed: 0.2, settle: 0), true)
        XCTAssertTrue(g.isDark)
    }

    func testDimNeedsTwoReadings() {
        var g = DarkRoomGate()
        XCTAssertEqual(g.feed(luma: 0.2, elapsed: 0.1, settle: 0), nil)
        XCTAssertEqual(g.feed(luma: 0.2, elapsed: 0.2, settle: 0), true)
    }

    func testSettlingReadingsAreIgnored() {
        var g = DarkRoomGate()
        XCTAssertEqual(g.feed(luma: 0.01, elapsed: 0.3, settle: 0.6), nil)
        XCTAssertEqual(g.feed(luma: 0.01, elapsed: 0.7, settle: 0.6), true)
    }

    func testOwnLightDoesNotSwitchItOff() {
        var g = DarkRoomGate()
        g.feed(luma: 0.05, elapsed: 0.2, settle: 0)
        // the screen lights the room to a mid level: stays on
        for i in 0..<30 { XCTAssertNil(g.feed(luma: 0.45, elapsed: 1 + Double(i) * 0.2, settle: 0)) }
        XCTAssertTrue(g.isDark)
    }

    func testRealDaylightSwitchesOffAfterMinOnAndRuns() {
        var g = DarkRoomGate()
        g.feed(luma: 0.05, elapsed: 0, settle: 0)
        XCTAssertEqual(g.feed(luma: 0.9, elapsed: 1, settle: 0), nil)
        XCTAssertEqual(g.feed(luma: 0.9, elapsed: 1.2, settle: 0), nil)
        XCTAssertEqual(g.feed(luma: 0.9, elapsed: 1.4, settle: 0), nil) // minOn not reached
        XCTAssertEqual(g.feed(luma: 0.9, elapsed: 3.2, settle: 0), false)
        XCTAssertTrue(!g.isDark)
    }

    func testOneBrightBlipDoesNotFlicker() {
        var g = DarkRoomGate()
        g.feed(luma: 0.05, elapsed: 0, settle: 0)
        XCTAssertEqual(g.feed(luma: 0.9, elapsed: 4, settle: 0), nil)
        XCTAssertEqual(g.feed(luma: 0.3, elapsed: 4.2, settle: 0), nil)
        XCTAssertTrue(g.isDark)
    }
}
