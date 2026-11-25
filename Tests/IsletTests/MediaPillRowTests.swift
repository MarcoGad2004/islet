import CoreGraphics
import XCTest
@testable import Islet

final class MediaPillRowTests: XCTestCase {
    /// Everything fits: the room left over is shared by the flexible pills; the fixed ones keep their width.
    func testSpreadsExtraRoom() {
        let w = PillRow.widths(ideal: [60, 60, 50, 54], fixed: [false, false, true, true], total: 468, spacing: 5)
        XCTAssertEqual(w[2], 50); XCTAssertEqual(w[3], 54)
        XCTAssertEqual(w.reduce(0, +) + 15, 468, accuracy: 0.01)
        XCTAssertEqual(w[0], w[1], accuracy: 0.01)
    }

    /// Too long: the short name keeps its whole width and the long one gives way.
    func testLongNameGivesWayFirst() {
        let w = PillRow.widths(ideal: [260, 60, 50, 54], fixed: [false, false, true, true], total: 300, spacing: 5)
        XCTAssertEqual(w[1], 60)
        XCTAssertEqual(w[2], 50); XCTAssertEqual(w[3], 54)
        XCTAssertEqual(w[0], 300 - 15 - 60 - 50 - 54, accuracy: 0.01)
    }

    /// Two long names share what is left equally.
    func testTwoLongNamesShareEqually() {
        let w = PillRow.widths(ideal: [200, 200, 50], fixed: [false, false, true], total: 300, spacing: 5)
        XCTAssertEqual(w[0], w[1], accuracy: 0.01)
        XCTAssertEqual(w[0] + w[1] + w[2] + 10, 300, accuracy: 0.01)
    }
}
