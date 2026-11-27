import XCTest
@testable import Islet

/// networkQuality's own output under a pseudo-terminal (`networkQuality -s`, macOS 27.2): one line redrawn with
/// carriage returns, then the summary.
final class SpeedTestParseTests: XCTestCase {
    private let running = "\u{1B}[2K\rDownlink: 66.462 Mbps, 0 RPM - Uplink: 0.000 Mbps, 0 RPM\r\u{1B}[2K\rDownlink: 71.856 Mbps, 136 RPM - Uplink: 0.000 Mbps, 0 RPM\r"
    private let summary = """
        \u{1B}[2K==== SUMMARY ====\r
        Uplink capacity: 16.162 Mbps\r
        Downlink capacity: 211.804 Mbps\r
        Uplink Responsiveness: Medium (235.025 milliseconds | 255 RPM)\r
        Downlink Responsiveness: Low (426.189 milliseconds | 140 RPM)\r
        Idle Latency: 66.557 milliseconds | 901 RPM\r

        """

    func testLiveTakesTheNewestWholeLine() {
        let f = SpeedTest.parseLive(running)
        XCTAssertEqual(f?.download, 71.856)
        XCTAssertEqual(f?.upload, 0)
        // A read that ends mid-line falls back to the last whole one.
        let cut = SpeedTest.parseLive(running + "\u{1B}[2K\rDownlink: 211.804 Mbps, 140 RPM - Uplink: 2")
        XCTAssertEqual(cut?.download, 71.856)
        XCTAssertNil(SpeedTest.parseLive("nothing here"))
    }

    func testLiveSeesTheUpload() {
        let f = SpeedTest.parseLive("\rDownlink: 211.804 Mbps, 140 RPM - Uplink: 28.486 Mbps, 159 RPM\r")
        XCTAssertEqual(f?.download, 211.804)
        XCTAssertEqual(f?.upload, 28.486)
    }

    func testSummary() {
        XCTAssertEqual(SpeedTest.parseSummary(running + summary), .done(.init(download: 211.804, upload: 16.162, latency: 66.557)))
    }

    func testNoSummaryFailsCleanly() {
        if case .failed = SpeedTest.parseSummary("") {} else { XCTFail("empty") }
        if case .failed = SpeedTest.parseSummary(running) {} else { XCTFail("cut off") }
        if case .failed = SpeedTest.parseSummary("Error: no network") {} else { XCTFail("error") }
    }
}
