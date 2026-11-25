import XCTest
@testable import Islet

final class StatsFixesTests: XCTestCase {
    func testPowerFlowsAreStillWhenNothingMoves() {
        let flows = PowerFlows(state: PowerMonitor.State(onAC: false), details: PowerMonitor.Details())
        XCTAssertFalse(flows.flowing)
    }

    func testPowerFlowsRunOnBatteryWithADraw() {
        var details = PowerMonitor.Details()
        details.systemWatts = 12
        XCTAssertTrue(PowerFlows(state: PowerMonitor.State(onAC: false), details: details).flowing)
    }

    func testMemoryRowsPastTheFootprintLimitKeepTheirResidentSize() {
        let line = (0..<(ProcessReader.footprintLimit + 5)).map { "\($0 + 1) 0.0 \(50_000 + $0) /Applications/A\($0).app/Contents/MacOS/A" }
        let rows = ProcessReader.parse(line.joined(separator: "\n"))
        XCTAssertEqual(rows.count, ProcessReader.footprintLimit + 5)
        XCTAssertEqual(rows.first?.residentKB, 50_000)
    }
}
