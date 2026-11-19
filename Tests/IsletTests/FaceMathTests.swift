import XCTest
@testable import Islet

final class FaceMathTests: XCTestCase {
    func testAlignerRecoversKnownTransform() {
        // Scale 1.7, rotate 12 degrees, shift: the fitted transform must map those points back onto the template.
        let t = CGAffineTransform(translationX: 300, y: 200).rotated(by: 12 * .pi / 180).scaledBy(x: 1.7, y: 1.7)
        let src = FaceAligner.template.map { $0.applying(t) }
        let fit = FaceAligner.transform(from: src)
        for (s, d) in zip(src, FaceAligner.template) {
            let p = s.applying(fit)
            XCTAssertEqual(p.x, d.x, accuracy: 1e-6)
            XCTAssertEqual(p.y, d.y, accuracy: 1e-6)
        }
    }

    func testCosineAndScore() {
        let a: [Float] = [1, 0, 0], b: [Float] = [0, 1, 0]
        XCTAssertEqual(FaceMatcher.cosine(a, a), 1, accuracy: 1e-6)
        XCTAssertEqual(FaceMatcher.cosine(a, b), 0, accuracy: 1e-6)
        XCTAssertEqual(FaceMatcher.score(a, enrolled: [a, a, a, b]), 1, accuracy: 1e-6)
        XCTAssertEqual(FaceMatcher.consistency([a, a, a]), 1, accuracy: 1e-6)
    }

    func testEnrolMetrics() {
        let m = Presentation.enrol.metrics(notchWidth: 190, notchHeight: 34)
        XCTAssertEqual(m.bw, 380)
        XCTAssertLessThanOrEqual(m.bh, Double(IslandLayout.expandedBodyHeight))
    }
}

final class IslandContentTests: XCTestCase {
    func testLevelSteps() {
        XCTAssertEqual(LevelState(kind: .volume, value: 0.5).steps, 8)
        XCTAssertEqual(LevelState(kind: .brightness, value: 1).steps, 16)
        XCTAssertEqual(LevelState(kind: .volume, value: 0).steps, 0)
    }

    func testChargeDurations() {
        XCTAssertEqual(ChargeEvent(kind: .connected, percent: 50).seconds, 3)
        XCTAssertEqual(ChargeEvent(kind: .full, percent: 100).seconds, 3)
        XCTAssertEqual(ChargeEvent(kind: .low, percent: 20).seconds, 4)
    }

    func testMediaPositionAdvancesWhilePlaying() {
        let t = Date()
        let playing = MediaInfo(bundleID: "x", title: "t", artist: "", album: "", playing: true, duration: 100, elapsed: 10, timestamp: t, rate: 1)
        XCTAssertEqual(playing.position(at: t.addingTimeInterval(5)), 15, accuracy: 0.001)
        var paused = playing; paused.playing = false
        XCTAssertEqual(paused.position(at: t.addingTimeInterval(5)), 10, accuracy: 0.001)
    }

    @MainActor func testPriorityAndLayout() {
        let store = IslandStore()
        store.setGeometry(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), width: 190, height: 34))
        XCTAssertEqual(store.presentation, .closed)
        store.showCharge(ChargeEvent(kind: .connected, percent: 50))
        XCTAssertEqual(store.presentation, .chin) // no layout check: chin
        store.showLevel(LevelState(kind: .volume, value: 0.5))
        guard case .level = store.content else { return XCTFail("level should outrank charging") }
        XCTAssertEqual(store.presentation, .chin)
        store.layoutCheck = { true }
        store.recomputeLayout()
        store.playUnlock()
        guard case .unlock = store.content else { return XCTFail("unlock should outrank level") }
        XCTAssertEqual(store.presentation, .lockWings) // the unlock animation uses the lock-screen bar
    }

    @MainActor func testNoNotchHangsUnderTheMenuBarIcon() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // An icon near the right edge: the island moves in so the 500 pt panel stays on screen.
        let g = NotchGeometry.underMenuBar(anchorX: 1400, menuBarBottom: 876, screen: screen)
        XCTAssertTrue(g.virtual)
        XCTAssertEqual(g.screenFrame.maxY, 876)
        XCTAssertEqual(g.screenFrame.midX, 1440 - 258)
        XCTAssertEqual(NotchGeometry.underMenuBar(anchorX: 900, menuBarBottom: 876, screen: screen).screenFrame.midX, 900)

        // Idle: nothing shows. Open: a flat card as wide as its body, with no stem or inner curves.
        let closed = IslandStore.underMenuBar(Presentation.closed.metrics(notchWidth: 100, notchHeight: 32), .closed)
        XCTAssertEqual(closed.height, 0)
        let open = IslandStore.underMenuBar(Presentation.expanded.metrics(notchWidth: 100, notchHeight: 32), .expanded)
        XCTAssertEqual(open.sw, open.bw)
        XCTAssertEqual(open.ic, 0)

        // Nothing to cover under the menu bar: notices use the wide bar, not the chin.
        let store = IslandStore()
        store.layoutCheck = { store.geometry?.virtual == true }
        store.setGeometry(g)
        store.showCharge(ChargeEvent(kind: .connected, percent: 50))
        XCTAssertEqual(store.presentation, .wings)
    }

    @MainActor func testBezelModeFloatsUnderTheMenuBar() {
        let g = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), width: 100, height: 34, mode: .bezel, menuBarHeight: 24)
        XCTAssertEqual(g.floatTop, 34)
        // Idle: tucked above the edge. Orb: hangs from the edge down to where cards float. Notices: float.
        let closed = IslandStore.floating(Presentation.closed.metrics(notchWidth: 100, notchHeight: 34), .closed, floatTop: 34)
        XCTAssertLessThan(closed.y + closed.height, 0)
        let orb = IslandStore.floating(Presentation.peek.metrics(notchWidth: 100, notchHeight: 34), .peek, floatTop: 34)
        XCTAssertEqual(orb.y, 0)
        XCTAssertEqual(orb.height, 64)
        let panel = IslandStore.floating(Presentation.expanded.metrics(notchWidth: 100, notchHeight: 34), .expanded, floatTop: 34)
        XCTAssertEqual(panel.y, 34)
        XCTAssertEqual(panel.sw, panel.bw)

        let store = IslandStore()
        store.layoutCheck = { true }
        store.setGeometry(g)
        // Music doesn't stay up without a notch; a notice still shows.
        store.setMedia(MediaInfo(bundleID: "x", title: "t", artist: "", album: "", playing: true, duration: 100, elapsed: 0, timestamp: Date(), rate: 1))
        XCTAssertNil(store.content)
        store.showCharge(ChargeEvent(kind: .connected, percent: 50))
        XCTAssertEqual(store.presentation, .wings)
        // The hover strip in the middle of the menu bar counts as over the island.
        XCTAssertTrue(store.isOverIsland(globalPoint: CGPoint(x: 720, y: 890)))
        XCTAssertFalse(store.isOverIsland(globalPoint: CGPoint(x: 300, y: 890)))
    }

    @MainActor func testLockScreenShowsTheLockBar() {
        let store = IslandStore()
        store.setGeometry(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), width: 190, height: 34))
        store.setLockScreen(true)
        guard case .locked = store.content else { return XCTFail("locked content expected") }
        XCTAssertEqual(store.presentation, .lockWings) // always the wide bar on the lock screen, never the chin
    }

    func testLockBarIsTallerThanTheNotchAndScanKeepsIt() {
        let bar = Presentation.lockWings.metrics(notchWidth: 190, notchHeight: 34)
        XCTAssertEqual(bar.height, 34 + Double(IslandLayout.lockBarExtra))
        XCTAssertEqual(bar.width, 190 + IslandLayout.wingsExtra)
        let scan = Presentation.scan.metrics(notchWidth: 190, notchHeight: 34)
        XCTAssertEqual(scan.sh, bar.sh) // the padlock must not move when the scan drops down
        XCTAssertEqual(scan.width, bar.width)
    }
}

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("v1.1", than: "1.0"))
        XCTAssertTrue(Updater.isNewer("1.10", than: "1.9"))
        XCTAssertTrue(Updater.isNewer("v2", than: "1.9.9"))
        XCTAssertFalse(Updater.isNewer("v1.0", than: "1.0"))
        XCTAssertFalse(Updater.isNewer("1.0", than: "1.0.1"))
    }
}

final class LevelLayoutTests: XCTestCase {
    @MainActor func testLevelsUseTheWideBarWhenItFitsAndTheChinOtherwise() {
        let store = IslandStore()
        store.setGeometry(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), width: 190, height: 34))
        store.showLevel(LevelState(kind: .volume, value: 0.5))
        XCTAssertEqual(store.presentation, .chin)
        store.layoutCheck = { true }
        store.recomputeLayout()
        XCTAssertEqual(store.presentation, .levelWings)
        let m = Presentation.levelWings.metrics(notchWidth: 190, notchHeight: 34)
        XCTAssertEqual(m.sw, 310); XCTAssertEqual(m.bw, 310); XCTAssertEqual(m.bh, 26)
    }

    func testFineStepsFillPartially() {
        XCTAssertEqual(LevelState(kind: .volume, value: 21.0 / 64).value * 16, 5.25, accuracy: 0.0001)
    }
}

final class EventLayoutTests: XCTestCase {
    @MainActor func testEventsUseTheWideBarOnlyWhenItFits() {
        let store = IslandStore()
        store.setGeometry(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), width: 190, height: 34))
        store.showEvent(IslandEvent(kind: .wifi, icon: "wifi", title: "Home", detail: "Connected"))
        XCTAssertEqual(store.presentation, .chin)
        store.layoutCheck = { true }          // narrow wings fit, but not the 128 pt the event bar needs
        store.recomputeLayout()
        XCTAssertEqual(store.presentation, .chin)
        store.eventLayoutCheck = { true }
        store.recomputeLayout()
        XCTAssertEqual(store.presentation, .eventWings)
        let m = Presentation.eventWings.metrics(notchWidth: 190, notchHeight: 34)
        XCTAssertEqual(m.sw, 190 + 240); XCTAssertEqual(m.bh, 0)
    }

    @MainActor func testNoNoticeWhileThePanelIsInUse() {
        let store = IslandStore()
        store.setGeometry(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), width: 190, height: 34))
        store.layoutCheck = { true }
        store.recomputeLayout()
        store.expand()
        store.showEvent(IslandEvent(kind: .hotspot, icon: "personalhotspot", title: "Phone", detail: "Hotspot"))
        XCTAssertNil(store.event)
        store.collapse()
        store.showEvent(IslandEvent(kind: .hotspot, icon: "personalhotspot", title: "Phone", detail: "Hotspot"))
        XCTAssertNil(store.event) // just closed: still the user's own doing
    }

    @MainActor func testHotspotUsesTheLevelBar() {
        let store = IslandStore()
        store.setGeometry(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), width: 190, height: 34))
        store.layoutCheck = { true }
        store.recomputeLayout()
        store.showEvent(IslandEvent(kind: .hotspot, icon: "personalhotspot", title: "Phone", detail: "Hotspot"))
        XCTAssertEqual(store.presentation, .levelWings)
        XCTAssertTrue(WiFiController.looksLikeHotspot("Marco’s iPhone Duo"))
        XCTAssertFalse(WiFiController.looksLikeHotspot("eduroam"))
    }

    @MainActor func testJoinProgressShowsWhenThePanelCloses() {
        let store = IslandStore()
        store.setGeometry(NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), width: 190, height: 34))
        store.layoutCheck = { true }
        store.recomputeLayout()
        store.expand()
        store.showProgress(ConnectionProgress(name: "Phone", hotspot: true, state: .working("Asking Phone…")))
        XCTAssertEqual(store.presentation, .expanded)
        store.collapse()
        XCTAssertEqual(store.presentation, .levelWings) // unlike a notice, progress isn't held back after closing
        store.showProgress(ConnectionProgress(name: "Phone", hotspot: true, state: .failed("Phone didn't answer.")))
        XCTAssertEqual(store.content?.kind, "progress") // updates in place
        store.layoutCheck = { false }
        store.recomputeLayout()
        XCTAssertEqual(store.presentation, .chin)
    }

    func testVersionOrderingStillWorks() { XCTAssertTrue(Updater.isNewer("v1.1", than: "1.0")) }
}
