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
}
