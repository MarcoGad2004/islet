import XCTest
@testable import Islet

final class LiveActivityTests: XCTestCase {
    func testCadenceCard() throws {
        // The texts of the real card, in the order Accessibility gives them (RESEARCH.md Q49), the "!" symbol already left out.
        let texts = ["Check capital one shopping bonus", "OVERDUE", "Reminder went off at 9:00 AM", "1:37:51", "Important", "5X tire bonus"]
        let card = try XCTUnwrap(LiveActivityWatcher.card(texts: texts, buttons: ["Complete"], value: "1:37:51"))
        XCTAssertEqual(card.title, "Check capital one shopping bonus")
        XCTAssertEqual(card.flag, "OVERDUE")
        XCTAssertEqual(card.lines, ["Reminder went off at 9:00 AM", "Important", "5X tire bonus"])
        XCTAssertEqual(card.buttons, ["Complete"])
    }

    func testValueAndFlag() {
        XCTAssertTrue(LiveActivityWatcher.isValue("1:37:23"))
        XCTAssertTrue(LiveActivityWatcher.isValue("12:04"))
        XCTAssertFalse(LiveActivityWatcher.isValue("9:00 AM"))
        XCTAssertTrue(LiveActivityWatcher.isFlag("LIVE"))
        XCTAssertFalse(LiveActivityWatcher.isFlag("Important"))
        XCTAssertFalse(LiveActivityWatcher.isFlag("A"))
        XCTAssertFalse(LiveActivityWatcher.isFlag("4TH"))
    }

    func testNoTextIsNoCard() {
        XCTAssertNil(LiveActivityWatcher.card(texts: ["12:04"], buttons: [], value: "12:04"))
        // A value that isn't a time (a score) stays out once it matches the menu bar's.
        XCTAssertEqual(LiveActivityWatcher.card(texts: ["Lakers at Celtics", "98–101"], buttons: [], value: "98–101")?.lines, [])
    }
}
