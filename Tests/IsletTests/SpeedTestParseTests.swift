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
        XCTAssertEqual(f, .init(download: 71.856, downloadRPM: 136, upload: 0, uploadRPM: 0))
        // A read that ends mid-line falls back to the last whole one.
        let cut = SpeedTest.parseLive(running + "\u{1B}[2K\rDownlink: 211.804 Mbps, 140 RPM - Uplink: 2")
        XCTAssertEqual(cut?.download, 71.856)
        XCTAssertNil(SpeedTest.parseLive("nothing here"))
    }

    func testLiveSeesTheUpload() {
        let f = SpeedTest.parseLive("\rDownlink: 211.804 Mbps, 140 RPM - Uplink: 28.486 Mbps, 159 RPM\r")
        XCTAssertEqual(f, .init(download: 211.804, downloadRPM: 140, upload: 28.486, uploadRPM: 159))
    }

    @MainActor func testLiveTextShowsThePing() {
        var l = SpeedTest.Live(download: 71.856)
        XCTAssertEqual(SpeedTest.liveText(l), "↓ 71.9 Mbps")
        l.ping = 60_000 / 186
        XCTAssertEqual(SpeedTest.liveText(l), "↓ 71.9 Mbps  323 ms")
        l.uploading = true; l.upload = 16.2
        XCTAssertEqual(SpeedTest.liveText(l), "↓ 71.9 Mbps  ↑ 16.2 Mbps  323 ms")
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
