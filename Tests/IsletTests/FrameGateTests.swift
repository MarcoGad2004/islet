import XCTest
@testable import Islet

final class FrameGateTests: XCTestCase {
    func testEveryFrameWhileAFaceIsInView() {
        let g = FrameGate(after: 3, every: 3)
        for _ in 0..<20 { XCTAssertTrue(g.shouldAnalyze()); g.note(face: true) }
    }

    func testThinsOutOnlyAfterSeveralMissesInARow() {
        let g = FrameGate(after: 3, every: 3)
        for _ in 0..<3 { XCTAssertTrue(g.shouldAnalyze()); g.note(face: false) }
        let analysed = (0..<9).filter { _ in g.shouldAnalyze() }.count
        XCTAssertEqual(analysed, 3)
    }

    func testAFaceBringsEveryFrameBack() {
        let g = FrameGate(after: 2, every: 3)
        for _ in 0..<2 { _ = g.shouldAnalyze(); g.note(face: false) }
        g.note(face: true)
        XCTAssertTrue(g.shouldAnalyze())
        XCTAssertTrue(g.shouldAnalyze())
    }

    func testCancelledEnrolmentNeverFinishes() throws {
        let finished = expectation(description: "finish"); finished.isInverted = true
        guard let embedder = FaceEmbedder() else { throw XCTSkip("model not in the bundle") }
        let e = EnrolmentEngine(embedder: embedder, onUpdate: { _ in }, onFinish: { _ in finished.fulfill() })
        e.cancel()
        e.handle(nil)
        wait(for: [finished], timeout: 0.2)
    }
}
