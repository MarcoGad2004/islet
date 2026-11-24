import XCTest
@testable import Islet

/// Names and charge from `system_profiler SPBluetoothDataType -json` (BluetoothController.parseDetails).
final class BluetoothDetailsTests: XCTestCase {
    func testReadsNamesAndCharge() throws {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"Marco’s AirPods Pro":{"device_address":"38:C4:3A:16:FF:CD",
          "device_batteryLevelCase":"67%","device_batteryLevelLeft":"81%","device_batteryLevelRight":"82%"}},
          {"Magic Mouse":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelMain":"15%"}}],
          "device_not_connected":[{"Bedroom":{"device_address":"F4:34:F0:16:3C:56"}}]}]}
        """
        let d = try XCTUnwrap(BluetoothController.parseDetails(Data(json.utf8)))
        let pods = try XCTUnwrap(d["38:c4:3a:16:ff:cd"])
        XCTAssertEqual(pods.name, "Marco’s AirPods Pro")
        XCTAssertEqual(pods.battery, BTBattery(left: 81, right: 82, caseLevel: 67, single: nil))
        XCTAssertEqual(pods.battery?.main, 81)
        XCTAssertEqual(d["aa:bb:cc:dd:ee:ff"]?.battery?.main, 15)
        XCTAssertEqual(d["f4:34:f0:16:3c:56"]?.name, "Bedroom")
        XCTAssertNil(d["f4:34:f0:16:3c:56"]?.battery)
        XCTAssertNil(BluetoothController.parseDetails(Data("nonsense".utf8)))
    }
}
