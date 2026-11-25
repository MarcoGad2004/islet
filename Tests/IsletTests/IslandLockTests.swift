import XCTest
@testable import Islet

@MainActor
final class IslandLockTests: XCTestCase {
    func testLockingClosesAnOpenPanel() {
        let store = IslandStore()
        store.expand()
        XCTAssertTrue(store.expanded)
        store.setLockScreen(true)
        XCTAssertFalse(store.expanded)
    }

    func testPausingClosesAnOpenPanel() {
        let store = IslandStore()
        store.expand()
        store.setPaused(true)
        XCTAssertFalse(store.expanded)
    }

    func testAScanClosesAnOpenPanel() {
        let store = IslandStore()
        store.expand()
        store.setBase(.scan)
        XCTAssertFalse(store.expanded)
    }
}
