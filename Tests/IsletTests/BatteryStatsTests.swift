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
        // With a charge limit: the time to the limit, and the limit right under it.
        var limited = PowerMonitor.Details()
        limited.chargeLimit = 85
        limited.currentMAh = 3000; limited.fullMAh = 6000; limited.voltage = 12; limited.batteryWatts = 36
        let toLimit = BatteryStatsView.chargeRows(state(50, ac: true, charging: true), limited, unplugged: nil)
        XCTAssertEqual(toLimit.map(\.0), ["Time to 85%", "Charge Limit"])
        XCTAssertEqual(toLimit[0].1, BatteryStatsView.duration(42)) // 36 Wh to 61.2 Wh at 36 W
    }

    func testIconIsTemplateUnlessColoured() {
        XCTAssertTrue(MenuBarBattery.image(percent: 50, charging: false, onAC: false, lowPower: false).isTemplate)
        XCTAssertFalse(MenuBarBattery.image(percent: 5, charging: false, onAC: false, lowPower: false).isTemplate)
        XCTAssertFalse(MenuBarBattery.image(percent: 50, charging: false, onAC: false, lowPower: true).isTemplate)
        // Green while charging; plugged in but not charging goes back to the menu bar's colour.
        XCTAssertFalse(MenuBarBattery.image(percent: 5, charging: true, onAC: true, lowPower: false).isTemplate)
        XCTAssertTrue(MenuBarBattery.image(percent: 80, charging: false, onAC: true, lowPower: false).isTemplate)
    }

    func testTemperatureReadsOrIsAbsent() {
        // On a MacBook the SMC answers with a room-ish temperature; elsewhere nothing.
        if let t = SMCSensors.temperature() { XCTAssertTrue((5...70).contains(t), "\(t)") }
        // The Mac's draw is always there; the battery's own sensor isn't kept in step with it, which is why the
        // diagram works the battery's share out from the other two.
        if let p = SMCSensors.power() { XCTAssertGreaterThan(p.system, 0) }
    }

    /// The diagram's labels add up whichever way the power goes.
    func testPowerFlowsAddUp() {
        func details(_ system: Double, _ input: Double?, _ battery: Double?) -> PowerMonitor.Details {
            var d = PowerMonitor.Details()
            d.systemWatts = system; d.adapterInWatts = input; d.batteryWatts = battery
            return d
        }
        // Charging: 57.6 in, 10.6 to the Mac, 47 to the battery.
        let charging = PowerFlows(state: state(33, ac: true, charging: true), details: details(10.6, 57.6, 47))
        XCTAssertEqual(charging.charger, (charging.mac ?? 0) + charging.chargerToBattery)
        XCTAssertEqual(charging.chargerToBattery, 47)
        XCTAssertEqual(charging.batteryToMac, 0)
        // A weak charger: the battery makes up the rest.
        let weak = PowerFlows(state: state(70, ac: true), details: details(45, 30, -15))
        XCTAssertEqual(weak.chargerToMac, 30)
        XCTAssertEqual(weak.batteryToMac, 15)
        XCTAssertEqual(weak.mac, 45)
        // On battery, small numbers keep a decimal and still add up.
        let battery = PowerFlows(state: state(30, ac: false), details: details(6.54, nil, -6.4))
        XCTAssertEqual(battery.batteryToMac, 6.5, accuracy: 0.001)
        XCTAssertEqual(battery.mac ?? 0, 6.5, accuracy: 0.001)
        XCTAssertNil(battery.charger)
        // Plugged in and resting: everything from the charger, nothing to the battery.
        let resting = PowerFlows(state: state(85, ac: true), details: details(9.1, 9.2, 0))
        XCTAssertEqual(resting.chargerToBattery, 0)
        XCTAssertEqual(resting.batteryToMac, 0)
    }

    /// Faster with more power, never racing, and a change of speed never moves the dashes backwards.
    func testFlowSpeed() {
        XCTAssertLessThan(FlowClock.speed(6), FlowClock.speed(50))
        XCTAssertEqual(FlowClock.speed(500), 30, accuracy: 0.001)
        let clock = FlowClock()
        var t = Date(timeIntervalSinceReferenceDate: 0)
        var last = clock.tick(t, watts: [5])[0]
        for step in 0..<60 {
            t += 1.0 / 60
            let now = clock.tick(t, watts: [step < 30 ? 5 : 90])[0]
            XCTAssertGreaterThan(now, last)
            last = now
        }
    }
}
