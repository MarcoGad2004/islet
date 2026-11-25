import XCTest
@testable import Islet

final class UpdateVersionRangeTests: XCTestCase {
    private func r(_ tag: String, _ notes: String = "notes", dmg: Bool = true) -> Updater.ReleaseInfo {
        .init(tag: tag, notes: notes, dmg: dmg ? URL(fileURLWithPath: "/tmp/\(tag).dmg") : nil)
    }

    func testNewestIgnoresListOrderAndPicksHighest() {
        let list = [r("v1.5.0"), r("v1.6.0"), r("v1.4.1"), r("v1.10.0"), r("v1.9.0")]
        XCTAssertEqual(Updater.newest(of: list)?.tag, "v1.10.0")
    }

    func testNewestSkipsReleaseWithoutDownload() {
        XCTAssertEqual(Updater.newest(of: [r("v1.7.0", dmg: false), r("v1.6.0")])?.tag, "v1.6.0")
    }

    func testNotesCoverEveryVersionNewestFirst() {
        let list = [r("v1.6", "six"), r("v1.5", "five"), r("v1.4", "four"), r("v1.3", "three")]
        let out = Updater.combinedNotes(list, after: "1.4", upTo: "v1.6")
        XCTAssertEqual(out, "## 1.6\n\nsix\n\n## 1.5\n\nfive")
    }

    func testSingleStepKeepsNotesUnchanged() {
        XCTAssertEqual(Updater.combinedNotes([r("v1.6", "six\n- a"), r("v1.5", "five")], after: "1.5", upTo: "v1.6"), "six\n- a")
    }

    func testMissingVersionsAndEmptyNotesAreSkipped() {
        let list = [r("v1.7", "seven"), r("v1.6", "  \n"), r("v1.4", "four")] // 1.5 isn't on GitHub, 1.6 has no notes
        XCTAssertEqual(Updater.combinedNotes(list, after: "1.3", upTo: "v1.7"), "## 1.7\n\nseven\n\n## 1.4\n\nfour")
        XCTAssertEqual(Updater.combinedNotes([r("v1.4")], after: "1.4", upTo: "v1.4"), "")
    }

    func testReleasesAboveTheChosenOneAreNotIncluded() {
        XCTAssertEqual(Updater.combinedNotes([r("v1.7", "seven"), r("v1.6", "six")], after: "1.5", upTo: "v1.6"), "six")
    }
}
