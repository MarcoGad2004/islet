import AppKit
import XCTest
@testable import Islet

/// Messages' `attributedBody` read by hand (MessagesDB.typedstreamString), checked against what NSArchiver writes.
final class MessagesTextTests: XCTestCase {
    private func archived(_ s: String, attributes: Bool = true) -> Data {
        let a = NSMutableAttributedString(string: s)
        // Messages stores attributes alongside the text (a part index, links, mentions): they must not get in the way.
        if attributes, !s.isEmpty {
            a.addAttribute(NSAttributedString.Key("__kIMMessagePartAttributeName"), value: 0, range: NSRange(location: 0, length: a.length))
            a.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 0, length: min(3, a.length)))
        }
        return NSArchiver.archivedData(withRootObject: a)
    }

    func testReadsWhatNSArchiverWrites() {
        let samples = [
            "Hi",
            "On my way, see you in 10 🙂",
            String(repeating: "a", count: 127),
            String(repeating: "b", count: 128),
            String(repeating: "Long message. ", count: 40),
            String(repeating: "é👍🏽", count: 30),
            String(repeating: "x", count: 70_000),
            "Line one\nLine two",
        ]
        for s in samples {
            let data = archived(s)
            XCTAssertEqual(MessagesDB.typedstreamString(data), s, "\(s.prefix(20))… (\(s.utf8.count) bytes)")
            XCTAssertEqual(MessagesDB.typedstreamString(archived(s, attributes: false)), s)
        }
    }

    func testNeverCrashesOnDamagedBodies() {
        let good = archived("Damaged body test, long enough to cut in many places")
        for cut in stride(from: 0, to: good.count, by: 3) {
            _ = MessagesDB.typedstreamString(good.prefix(cut))
        }
        XCTAssertNil(MessagesDB.typedstreamString(Data()))
        XCTAssertNil(MessagesDB.typedstreamString(Data("not a typedstream".utf8)))
        XCTAssertNil(MessagesDB.typedstreamString(Data("NSString".utf8)))
    }

    func testTextColumnWins() {
        XCTAssertEqual(MessagesDB.text("plain", archived("archived")), "plain")
        XCTAssertEqual(MessagesDB.text(nil, archived("archived")), "archived")
        XCTAssertEqual(MessagesDB.text("", archived("archived")), "archived")
    }
}
