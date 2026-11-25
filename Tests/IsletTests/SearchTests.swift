import XCTest
@testable import Islet

final class SearchTests: XCTestCase {
    private func m(_ name: String, _ q: String) -> (score: Double, marks: [Int])? { SearchMatch.match(name, SearchMatch.query(q)) }

    func testMatchOrder() throws {
        // A name's start beats a word's start, which beats the middle of a word, which beats letters in order.
        let start = try XCTUnwrap(m("Notes", "no"))
        let word = try XCTUnwrap(m("Safari Reading List to Notes", "no"))
        let inside = try XCTUnwrap(m("Keynote", "no"))
        let letters = try XCTUnwrap(m("Xcode", "xcd"))
        XCTAssertGreaterThan(start.score, word.score)
        XCTAssertGreaterThan(word.score, inside.score)
        XCTAssertGreaterThan(inside.score, letters.score)
        XCTAssertEqual(start.marks, [0, 1])
        XCTAssertEqual(letters.marks, [0, 1, 3])
    }

    func testEdgeCases() {
        XCTAssertNotNil(m("No", "no"))          // exactly as long as the text
        XCTAssertNil(m("N", "no"))              // shorter than the text
        XCTAssertNil(m("Send ETA Home", "sh"))  // letters in order only from three letters
        XCTAssertNil(m("Safari", ""))
        XCTAssertNotNil(m("Wi-Fi", "fi"))       // after a hyphen is a word's start
        XCTAssertNil(m("System Information", "mom"))  // letters in order must start a word
        XCTAssertNotNil(m("Xcode", "xcd"))
    }

    func testContactKind() {
        let c = SearchItem(id: "contact:1", kind: .contact, name: "Mom", detail: "")
        XCTAssertEqual(c.kindLabel, "Contact")
        XCTAssertEqual(SearchItem(id: "contact:2", kind: .contact, name: "Tim", detail: "Apple").kindLabel, "Apple")
    }

    func testContactActionWords() {
        XCTAssertEqual(ContactAction.parse("call mom")?.0, .call)
        XCTAssertEqual(ContactAction.parse("call mom")?.1, "mom")
        XCTAssertEqual(ContactAction.parse("Text  Joy's Mom")?.0, .message)
        XCTAssertEqual(ContactAction.parse("text  Joy's Mom")?.1, "Joy's Mom")
        XCTAssertEqual(ContactAction.parse("facetime dad")?.0, .faceTime)
        XCTAssertEqual(ContactAction.parse("email tim")?.0, .email)
        XCTAssertNil(ContactAction.parse("call"))        // no name yet
        XCTAssertNil(ContactAction.parse("calligraphy")) // not the word on its own
        XCTAssertNil(ContactAction.parse("notes app"))
    }

    func testContactActionsNeedWhatsSaved() {
        var c = SearchItem(id: "contact:1", kind: .contact, name: "Mom")
        XCTAssertEqual(c.contactActions, [])
        c.email = "mom@example.com"
        XCTAssertEqual(c.contactActions, [.message, .faceTime, .email])
        c.phone = "+1 555 0100"
        XCTAssertEqual(c.contactActions, [.message, .call, .faceTime, .email])
    }

    func testCalculator() {
        XCTAssertEqual(SearchCalculator.evaluate("12*7.5"), 90)
        XCTAssertEqual(SearchCalculator.evaluate("(3+4)/2"), 3.5)
        XCTAssertEqual(SearchCalculator.evaluate("2^3^2"), 512)
        XCTAssertEqual(SearchCalculator.evaluate("15% * 80"), 12)
        XCTAssertEqual(SearchCalculator.evaluate("-4 + 10"), 6)
        XCTAssertEqual(SearchCalculator.evaluate("1,200 x 3"), 3600)
        XCTAssertNil(SearchCalculator.evaluate("12"))      // a number alone isn't a sum
        XCTAssertNil(SearchCalculator.evaluate("-4"))
        XCTAssertNil(SearchCalculator.evaluate("xcd"))
        XCTAssertNil(SearchCalculator.evaluate("(1+2"))
        XCTAssertNil(SearchCalculator.evaluate("1/0"))     // not finite
        XCTAssertEqual(SearchCalculator.format(1234.5), "1,234.5")
    }

    func testWebSearchURL() {
        XCTAssertEqual(WebSearchEngine.duckDuckGo.url(for: "a b&c")?.absoluteString, "https://duckduckgo.com/?q=a%20b%26c")
    }

    func testSiriPrefix() {
        XCTAssertEqual(SiriQuestion.prefixed("siri what's on today"), "what's on today")
        XCTAssertEqual(SiriQuestion.prefixed("Siri, set a timer"), "set a timer")
        XCTAssertEqual(SiriQuestion.prefixed("SIRI: hi"), "hi")
        XCTAssertEqual(SiriQuestion.prefixed("siri"), "")
        XCTAssertNil(SiriQuestion.prefixed("sirius"))
        XCTAssertNil(SiriQuestion.prefixed("safari"))
    }

    func testQuestions() {
        XCTAssertTrue(SiriQuestion.isQuestion("what’s the weather this weekend"))
        XCTAssertTrue(SiriQuestion.isQuestion("how far is the moon"))
        XCTAssertTrue(SiriQuestion.isQuestion("moon distance?"))
        XCTAssertFalse(SiriQuestion.isQuestion("weather"))
        XCTAssertFalse(SiriQuestion.isQuestion("what"))
        XCTAssertFalse(SiriQuestion.isQuestion("isle"))
        XCTAssertFalse(SiriQuestion.isQuestion("?"))
    }

    func testCalculatorRefusesAWallOfBrackets() {
        XCTAssertNil(SearchCalculator.evaluate("1+" + String(repeating: "(", count: 50_000) + "1"))
        XCTAssertNil(SearchCalculator.evaluate("1+" + String(repeating: "-", count: 50_000) + "1"))
        XCTAssertEqual(SearchCalculator.evaluate("(3+4)*2"), 14)
    }
}
