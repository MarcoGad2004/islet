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

    func testEachEarbudInTheCase() throws {
        // Both in: flags 0xb. Left out: the plain message (status bit 5 clear) drops bit 1, the mirrored one (bit 5 set) bit 0.
        let both = try XCTUnwrap(EarbudsReading.decode(data("4c0007190124205599b531000404e2e33639520216ffcd06100000"))).reading
        XCTAssertTrue(both.leftIn && both.rightIn)
        let leftOutPlain = try XCTUnwrap(EarbudsReading.decode(data("4c00071901242051999531000404e2e33639520216ffcd06100000"))).reading
        XCTAssertFalse(leftOutPlain.leftIn); XCTAssertTrue(leftOutPlain.rightIn)
        let leftOut = try XCTUnwrap(EarbudsReading.decode(data("4c0007190124203199a531000404e2e33639520216ffcd06100000"))).reading
        XCTAssertFalse(leftOut.leftIn); XCTAssertTrue(leftOut.rightIn)
        let rightOut = try XCTUnwrap(EarbudsReading.decode(data("4c0007190124202599953200040408e33639520216ffcd06100000"))).reading
        XCTAssertTrue(rightOut.leftIn); XCTAssertFalse(rightOut.rightIn)
    }

    func testEachEarbudsOwnCharge() throws {
        // Status bit 5 clear: the left earbud is the high nibble (70%), the right the low one (90%).
        let plain = try XCTUnwrap(EarbudsReading.decode(data("4c0007190124205179 95 31000404e2".replacingOccurrences(of: " ", with: "") + "e33639520216ffcd06100000"))).reading
        XCTAssertEqual(plain.leftLevel, 70); XCTAssertEqual(plain.rightLevel, 90)
        // Bit 5 set (the mirrored message): the other way round.
        let mirrored = try XCTUnwrap(EarbudsReading.decode(data("4c0007190124203179 95 31000404e2".replacingOccurrences(of: " ", with: "") + "e33639520216ffcd06100000"))).reading
        XCTAssertEqual(mirrored.leftLevel, 90); XCTAssertEqual(mirrored.rightLevel, 70)
    }

    func testExactChargesFromMacOSReplaceTheBroadcastsTens() throws {
        let r = try XCTUnwrap(EarbudsReading.decode(data("4c0007190124205599b531000404e2e33639520216ffcd06100000"))).reading
        XCTAssertEqual(r.earbuds, 90)
        let merged = r.merged(with: ("Marco's AirPods Pro", BTBattery(left: 95, right: 96, caseLevel: 53)))
        XCTAssertEqual(merged.name, "Marco's AirPods Pro")
        XCTAssertEqual(merged.earbuds, 95)
        XCTAssertEqual(merged.caseLevel, 53)
        XCTAssertEqual(merged.leftLevel, 95)
        XCTAssertEqual(merged.rightLevel, 96)
        // Not connected (no figures): the broadcast's tens stay.
        XCTAssertEqual(r.merged(with: ("Marco's AirPods Pro", nil)).caseLevel, 50)
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
