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

final class BrowserSiteTests: XCTestCase {
    private func site(_ window: String, _ media: String = "I've Been Keeping This A Secret", app: String = "Zen") -> String? {
        BrowserSite.site(windowTitle: window, mediaTitle: media, appName: app)
    }

    func testSiteAfterTheTitle() {
        XCTAssertEqual(site("I've Been Keeping This A Secret - YouTube — Zen Browser"), "YouTube")
        XCTAssertEqual(site("I've Been Keeping This A Secret - YouTube"), "YouTube")
        XCTAssertEqual(site("(3) I've Been Keeping This A Secret - YouTube - Google Chrome", app: "Google Chrome"), "YouTube")
    }

    func testSiteBeforeTheTitle() {
        XCTAssertEqual(site("Twitch | I've Been Keeping This A Secret"), "Twitch")
    }

    func testNoMatchOrNoSite() {
        XCTAssertNil(site("Netflix"))
        XCTAssertNil(site("I've Been Keeping This A Secret — Zen Browser"))
        XCTAssertNil(site("I've Been Keeping This A Secret - Private Browsing", app: "Firefox"))
    }
}

final class MediaPositionTests: XCTestCase {
    func testUnknownPositionIsFlagged() {
        var m = MediaInfo(bundleID: "app.zen-browser.zen", title: "t", artist: "", album: "", playing: true, duration: 0, elapsed: 0, timestamp: Date(), rate: 1)
        XCTAssertTrue(m.positionKnown)
        m.positionKnown = false
        XCTAssertFalse(m.positionKnown)
    }
}

final class PlayerControlsTests: XCTestCase {
    func testParsesSpotify() {
        let a = PlayerControls.parse("true,false\n", app: .spotify)
        XCTAssertEqual(a?.shuffle, true); XCTAssertEqual(a?.repeatMode, 1)
        XCTAssertEqual(PlayerControls.parse("false,true", app: .spotify)?.repeatMode, 3)
    }

    func testParsesMusic() {
        XCTAssertEqual(PlayerControls.parse("true,all", app: .music)?.repeatMode, 3)
        XCTAssertEqual(PlayerControls.parse("false,one", app: .music)?.repeatMode, 2)
        XCTAssertEqual(PlayerControls.parse("false,off", app: .music)?.repeatMode, 1)
        XCTAssertNil(PlayerControls.parse("oops", app: .music))
    }

    func testRepeatCycles() {
        XCTAssertEqual(PlayerControls.nextRepeat(.music, from: 1), 3)
        XCTAssertEqual(PlayerControls.nextRepeat(.music, from: 3), 2)
        XCTAssertEqual(PlayerControls.nextRepeat(.music, from: 2), 1)
        XCTAssertEqual(PlayerControls.nextRepeat(.spotify, from: 1), 3)
        XCTAssertEqual(PlayerControls.nextRepeat(.spotify, from: 3), 1)
    }

    func testOnlyMusicAndSpotifyScript() {
        XCTAssertNotNil(PlayerControls.app("com.apple.Music")); XCTAssertNotNil(PlayerControls.app("com.spotify.client"))
        XCTAssertNil(PlayerControls.app("com.apple.podcasts")); XCTAssertNil(PlayerControls.app("app.zen-browser.zen"))
    }
}
