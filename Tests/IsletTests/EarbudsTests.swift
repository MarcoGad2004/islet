import XCTest
@testable import Islet

/// The AirPods case broadcast, as captured from a Pro 2 case (RESEARCH.md "AirPods case").
final class EarbudsTests: XCTestCase {
    private func data(_ hex: String) -> Data {
        Data(stride(from: 0, to: hex.count, by: 2).map { i in
            UInt8(hex[hex.index(hex.startIndex, offsetBy: i)...hex.index(hex.startIndex, offsetBy: i + 1)], radix: 16)!
        })
    }

    func testOpenCaseWithBothEarbuds() throws {
        // Lid open (byte 10 = 0x31), earbuds 90%, case 50%, both earbuds charging.
        let r = try XCTUnwrap(EarbudsReading.decode(data("4c0007190124205599b531000404e2e33639520216ffcd06100000")))
        XCTAssertTrue(r.open)
        XCTAssertEqual(r.reading.model, 0x2024)
        XCTAssertEqual(r.reading.name, "AirPods Pro 2")
        XCTAssertEqual(r.reading.earbuds, 90)
        XCTAssertEqual(r.reading.caseLevel, 50)
        XCTAssertTrue(r.reading.earbudsCharging)
        XCTAssertFalse(r.reading.caseCharging)
    }

    func testClosingBurstIsNotOpen() throws {
        let r = try XCTUnwrap(EarbudsReading.decode(data("4c0007190124205599b539000404e2e33639520216ffcd06100000")))
        XCTAssertFalse(r.open)
    }

    func testEarbudsInEarsAreNoCase() {
        // Case charge unknown (low nibble 0xF), as the earbuds send while worn.
        XCTAssertNil(EarbudsReading.decode(data("4c0007190124200baa8f100005056464ff395202000000061c0000")))
    }

    func testOtherMessagesAreIgnored() {
        XCTAssertNil(EarbudsReading.decode(data("4c000711061dfcc7bfb59bfb0b7af707fe2393d86f")))
        XCTAssertNil(EarbudsReading.decode(data("4c0010050b1c")))
    }

    func testSymbolsFollowTheModel() {
        let pro = EarbudsReading(model: 0x2024, name: "", pro: true, earbuds: nil, caseLevel: nil, earbudsCharging: false, caseCharging: false)
        XCTAssertEqual(pro.symbols.earbuds, "airpodspro")
        var gen4 = pro; gen4.model = 0x2019
        XCTAssertEqual(gen4.symbols.earbuds, "airpods.gen4")
        var pro3 = pro; pro3.model = 0x2027
        XCTAssertEqual(pro3.symbols.earbuds, "airpods.pro.gen3")
    }
}
