import CoreGraphics
import XCTest
@testable import Islet

final class MediaPillRowTests: XCTestCase {
    /// Everything fits: the room left over is shared by the flexible pills; the fixed ones keep their width.
    func testSpreadsExtraRoom() {
        let w = PillRow.widths(ideal: [60, 60, 50, 54], fixed: [false, false, true, true], total: 468, spacing: 5)
        XCTAssertEqual(w[2], 50); XCTAssertEqual(w[3], 54)
        XCTAssertEqual(w.reduce(0, +) + 15, 468, accuracy: 0.01)
        XCTAssertEqual(w[0], w[1], accuracy: 0.01)
    }

    /// Too long: the short name keeps its whole width and the long one gives way.
    func testLongNameGivesWayFirst() {
        let w = PillRow.widths(ideal: [260, 60, 50, 54], fixed: [false, false, true, true], total: 300, spacing: 5)
        XCTAssertEqual(w[1], 60)
        XCTAssertEqual(w[2], 50); XCTAssertEqual(w[3], 54)
        XCTAssertEqual(w[0], 300 - 15 - 60 - 50 - 54, accuracy: 0.01)
    }

    /// Two long names share what is left equally.
    func testTwoLongNamesShareEqually() {
        let w = PillRow.widths(ideal: [200, 200, 50], fixed: [false, false, true], total: 300, spacing: 5)
        XCTAssertEqual(w[0], w[1], accuracy: 0.01)
        XCTAssertEqual(w[0] + w[1] + w[2] + 10, 300, accuracy: 0.01)
    }
}

final class MediaKindTests: XCTestCase {
    func testBrowsersAreRecognised() {
        for id in ["com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary", "org.mozilla.firefox", "app.zen-browser.zen",
                   "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"] {
            XCTAssertTrue(MediaInfo.isBrowser(id), id)
        }
    }

    func testMusicAppsAreNot() {
        for id in ["com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.TV", "org.videolan.vlc"] {
            XCTAssertFalse(MediaInfo.isBrowser(id), id)
        }
    }

    func testSkipLength() {
        let t = Date()
        let web = MediaInfo(bundleID: "app.zen-browser.zen", title: "t", artist: "", album: "", playing: true, duration: 100, elapsed: 0, timestamp: t, rate: 1)
        let music = MediaInfo(bundleID: "com.spotify.client", title: "t", artist: "", album: "", playing: true, duration: 100, elapsed: 0, timestamp: t, rate: 1)
        XCTAssertEqual(web.skipSeconds, 10); XCTAssertEqual(music.skipSeconds, 15)
    }
}
