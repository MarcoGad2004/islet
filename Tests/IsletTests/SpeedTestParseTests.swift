import XCTest
@testable import Islet

final class SpeedTestParseTests: XCTestCase {
    func testParsesThroughputAndLatency() {
        let json = #"{"dl_throughput": 250000000, "ul_throughput": 40000000, "base_rtt": 12.5}"#
        XCTAssertEqual(SpeedTest.parse(Data(json.utf8)), .done(.init(download: 250, upload: 40, latency: 12.5)))
    }

    func testErrorAndGarbageFailCleanly() {
        if case .failed = SpeedTest.parse(Data(#"{"error_code": "timeout"}"#.utf8)) {} else { XCTFail("error_code") }
        if case .failed = SpeedTest.parse(Data("not json".utf8)) {} else { XCTFail("garbage") }
        if case .failed = SpeedTest.parse(Data("{}".utf8)) {} else { XCTFail("empty") }
    }
}
