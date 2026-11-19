import XCTest
@testable import Islet

final class PresentationMetricsTests: XCTestCase {
    func testShapesMatchDesign() {
        let nw = 190.0, nh = 34.0
        let wings = Presentation.wings.metrics(notchWidth: nw, notchHeight: nh)
        XCTAssertEqual(wings.width, nw + 120)
        XCTAssertEqual(wings.height, nh)

        let chin = Presentation.chin.metrics(notchWidth: nw, notchHeight: nh)
        XCTAssertEqual(chin.bw, 300)
        XCTAssertEqual(chin.bh, 36)

        let expanded = Presentation.expanded.metrics(notchWidth: nw, notchHeight: nh)
        XCTAssertEqual(expanded.bw, 500)
        XCTAssertEqual(expanded.height, nh + 216)
    }

    func testClosedIsTheNotch() {
        let m = Presentation.closed.metrics(notchWidth: 190, notchHeight: 34)
        XCTAssertEqual(m.width, 190)
        XCTAssertEqual(m.height, 34)
    }
}
