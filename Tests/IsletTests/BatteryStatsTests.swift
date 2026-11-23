import XCTest
@testable import Islet

/// The battery history behind the menu bar battery's stats, and the stats' wording.
@MainActor
final class BatteryStatsTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func state(_ percent: Int, ac: Bool, charging: Bool = false) -> PowerMonitor.State {
        var s = PowerMonitor.State()
        s.percent = percent
        s.onAC = ac
        s.charging = charging
        return s
    }

    func testParsesPowerdLog() {
        let log = """
        2026-11-23 09:37:41 -0700 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:41%) 95 secs
        2026-11-23 09:54:12 -0700 Assertions          \tSummary- [System: PrevIdle DeclUser SysAct kDisp] Using AC(Charge: 40)
        2026-11-23 09:55:00 -0700 Wake                \tsomething without a charge
        """
        let samples = BatteryHistory.parseLog(log, since: .distantPast)
        XCTAssertEqual(samples.map(\.percent), [41, 40])
        XCTAssertEqual(samples.map(\.onAC), [false, true])
        XCTAssertEqual(samples[1].time.timeIntervalSince(samples[0].time), 16 * 60 + 31)
    }

    func testRecordsChangesAndTicks() {
        let h = BatteryHistory(file: nil)
        h.record(state(50, ac: true), at: t0)
        h.record(state(50, ac: true), at: t0.addingTimeInterval(60)) // nothing new
        h.record(state(51, ac: true), at: t0.addingTimeInterval(120))
        h.record(state(51, ac: true), at: t0.addingTimeInterval(120 + BatteryHistory.interval))
        XCTAssertEqual(h.samples.map(\.percent), [50, 51, 51])
    }

    func testUnplugTime() {
        let h = BatteryHistory(file: nil)
        h.record(state(80, ac: true), at: t0)
        XCTAssertNil(h.unpluggedAt)
        h.record(state(80, ac: false), at: t0.addingTimeInterval(100))
        XCTAssertEqual(h.unpluggedAt, t0.addingTimeInterval(100))
        h.record(state(79, ac: false), at: t0.addingTimeInterval(200))
        XCTAssertEqual(h.unpluggedAt, t0.addingTimeInterval(100))
        h.record(state(79, ac: true), at: t0.addingTimeInterval(300))
        XCTAssertNil(h.unpluggedAt)
    }

    /// Islet started on battery: the log says when the charger came out.
    func testUnplugTimeFromLog() {
        let h = BatteryHistory(file: nil)
        let now = t0.addingTimeInterval(3 * 3600)
        h.record(state(60, ac: false), at: now)
        let logged = [
            BatteryHistory.Sample(time: t0, percent: 90, onAC: true),
            BatteryHistory.Sample(time: t0.addingTimeInterval(600), percent: 88, onAC: false),
            BatteryHistory.Sample(time: t0.addingTimeInterval(3600), percent: 75, onAC: false),
        ]
        h.merge(logged, now: now)
        XCTAssertEqual(h.unpluggedAt, t0.addingTimeInterval(600))
        XCTAssertEqual(h.samples.count, 4)
    }

    func testRecentCarriesTheChargeToBothEdges() {
        let h = BatteryHistory(file: nil)
        h.record(state(90, ac: false), at: t0)
        h.record(state(70, ac: false), at: t0.addingTimeInterval(13 * 3600))
        let now = t0.addingTimeInterval(14 * 3600)
        let recent = h.recent(hours: 12, now: now, current: state(65, ac: false))
        XCTAssertEqual(recent.first?.time, now.addingTimeInterval(-12 * 3600))
        XCTAssertEqual(recent.first?.percent, 90)
        XCTAssertEqual(recent.last?.percent, 65)
    }

    func testChargeRows() {
        var s = state(36, ac: false)
        s.minutesToEmpty = 187
        let rows = BatteryStatsView.chargeRows(s, PowerMonitor.Details(), unplugged: t0, now: t0.addingTimeInterval(26 * 3600 + 43 * 60))
        XCTAssertEqual(rows.map(\.0), ["Time Left", "Since Unplugged"])
        XCTAssertEqual(rows[0].1, BatteryStatsView.duration(187))
        XCTAssertTrue(rows[1].1.contains("26"))
        let charging = BatteryStatsView.chargeRows(state(40, ac: true, charging: true), PowerMonitor.Details(), unplugged: nil)
        XCTAssertEqual(charging.map(\.0), ["Time to Full"])
    }

    func testIconIsTemplateUnlessColoured() {
        XCTAssertTrue(MenuBarBattery.image(percent: 50, charging: false, onAC: false, lowPower: false).isTemplate)
        XCTAssertFalse(MenuBarBattery.image(percent: 5, charging: false, onAC: false, lowPower: false).isTemplate)
        XCTAssertFalse(MenuBarBattery.image(percent: 50, charging: false, onAC: false, lowPower: true).isTemplate)
        XCTAssertTrue(MenuBarBattery.image(percent: 5, charging: true, onAC: true, lowPower: false).isTemplate)
    }

    func testTemperatureReadsOrIsAbsent() {
        // On a MacBook the SMC answers with a room-ish temperature; elsewhere nothing.
        if let t = SMCSensors.temperature() { XCTAssertTrue((5...70).contains(t), "\(t)") }
        // The power sensors add up: what comes in goes to the Mac and the battery.
        if let p = SMCSensors.power(), let c = p.chargerIn, c > 1, let b = p.battery {
            XCTAssertEqual(c, p.system + b, accuracy: max(3, c * 0.1))
        }
    }
}
