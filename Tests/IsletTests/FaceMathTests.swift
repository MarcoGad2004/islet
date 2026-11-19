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
        XCTAssertEqual(store.presentation, .wings)
    }
}
