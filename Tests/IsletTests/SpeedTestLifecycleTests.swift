import XCTest
@testable import Islet

@MainActor
final class SpeedTestLifecycleTests: XCTestCase {
    private func settle(_ test: SpeedTest, until done: (SpeedTest) -> Bool) async {
        for _ in 0..<100 where !done(test) { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func testKeepsRunningWhilePanelIsClosed() async {
        let t = SpeedTest(tool: "/bin/sleep", arguments: ["3"])
        t.run()
        XCTAssertTrue(t.running)
        // Nothing the panel does on closing touches the test; it is still going a moment later.
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(t.running)
        t.cancel()
        await settle(t) { $0.state == .idle }
    }

    func testStopCancels() async {
        let t = SpeedTest(tool: "/bin/sleep", arguments: ["3"])
        t.run(); t.cancel()
        await settle(t) { !$0.running }
        XCTAssertEqual(t.state, .idle)
    }

    func testSleepCancels() async {
        let t = SpeedTest(tool: "/bin/sleep", arguments: ["3"])
        t.run()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await settle(t) { !$0.running }
        XCTAssertEqual(t.state, .idle)
    }

    func testNetworkChangeResetCancels() async {
        let t = SpeedTest(tool: "/bin/sleep", arguments: ["3"])
        t.run(); t.reset()
        await settle(t) { !$0.running }
        XCTAssertEqual(t.state, .idle)
    }
}
