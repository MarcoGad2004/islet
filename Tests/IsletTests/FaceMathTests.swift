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
