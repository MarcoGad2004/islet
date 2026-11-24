import XCTest
@testable import Islet

/// Mac Stats' readers' sums and the warning colours' rules (DESIGN.md "Mac Stats (1.7)").
final class MacStatsTests: XCTestCase {
    func testCPUUsageSplitsCoreTypes() throws {
        // Two efficiency cores then two performance cores: user, system, idle, nice.
        let a: CPUReader.Ticks = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
        let b: CPUReader.Ticks = [[60, 20, 20, 0], [40, 0, 50, 10], [0, 0, 100, 0], [10, 10, 80, 0]]
        let s = try XCTUnwrap(CPUReader.usage(from: a, to: b, efficiencyCount: 2))
        XCTAssertEqual(s.cores, [0.8, 0.5, 0, 0.2])
        XCTAssertEqual(s.efficiency, 0.65, accuracy: 1e-9)
        XCTAssertEqual(s.performance, 0.1, accuracy: 1e-9)
        XCTAssertEqual(s.user, 120.0 / 400, accuracy: 1e-9)   // nice counts as user
        XCTAssertEqual(s.system, 30.0 / 400, accuracy: 1e-9)
        XCTAssertEqual(s.total, 0.375, accuracy: 1e-9)
    }

    func testCPUUsageNeedsMatchingReadings() {
        XCTAssertNil(CPUReader.usage(from: [[0, 0, 0, 0]], to: [[1, 0, 0, 0], [1, 0, 0, 0]], efficiencyCount: 0))
        XCTAssertNil(CPUReader.usage(from: [[5, 5, 5, 5]], to: [[5, 5, 5, 5]], efficiencyCount: 0))
    }

    func testMemoryAddsUpLikeActivityMonitor() {
        let gb: UInt64 = 1 << 30, page: UInt64 = 16384, perGB = gb / page
        let m = MemorySample(total: 48 * gb, pageSize: page, anonymous: 20 * perGB, purgeable: 2 * perGB, wired: 4 * perGB,
                             compressor: 6 * perGB, swapUsed: 0, pressure: .normal)
        XCTAssertEqual(m.app, 18 * gb)
        XCTAssertEqual(m.used, 28 * gb)
        XCTAssertEqual(m.free, 20 * gb)
        XCTAssertEqual(m.fraction, 28.0 / 48, accuracy: 1e-9)
    }

    func testMemoryPressureFromKernelLevels() {
        XCTAssertEqual(MemoryPressure(kernelLevel: 1), .normal)
        XCTAssertEqual(MemoryPressure(kernelLevel: 2), .warning)
        XCTAssertEqual(MemoryPressure(kernelLevel: 4), .critical)
    }

    func testEnergyUnits() {
        XCTAssertEqual(EnergyReader.joules(4040, unit: "mJ"), 4.04, accuracy: 1e-9)
        XCTAssertEqual(EnergyReader.joules(311_874_029, unit: "nJ"), 0.311874029, accuracy: 1e-12)
        XCTAssertEqual(EnergyReader.joules(5, unit: "W"), 0)
    }

    func testGPUClientCreator() {
        XCTAssertEqual(GPUReader.parseCreator("pid 616, WindowServer")?.0, 616)
        XCTAssertEqual(GPUReader.parseCreator("pid 616, WindowServer")?.1, "WindowServer")
        XCTAssertNil(GPUReader.parseCreator("WindowServer"))
    }

    func testParsesPS() {
        let rows = ProcessReader.parse("""
          616  38.6 667936 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
        40607  19.7 269072 /Applications/Dynamic Peninsula.app/Contents/MacOS/Dynamic Peninsula
        garbage
        """)
        XCTAssertEqual(rows, [
            .init(pid: 616, cpu: 38.6, residentKB: 667_936, name: "WindowServer",
                  path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
            .init(pid: 40607, cpu: 19.7, residentKB: 269_072, name: "Dynamic Peninsula",
                  path: "/Applications/Dynamic Peninsula.app/Contents/MacOS/Dynamic Peninsula"),
        ])
    }

    func testTemperaturesIgnoreUnusedSensors() {
        let v = ["Tp01": 40, "Tp02": 60, "Tp0m": 5.2, "Tp0z": 400]
        XCTAssertEqual(ThermalReader.mean(Array(v.keys), v), 50)
        XCTAssertEqual(ThermalReader.hottest(Array(v.keys), v), 60)
        XCTAssertNil(ThermalReader.mean(["Tg01"], v))
    }

    func testLevels() {
        XCTAssertEqual(StatLevel(load: 0.7), .normal)
        XCTAssertEqual(StatLevel(load: 0.71), .warning)
        XCTAssertEqual(StatLevel(load: 0.91), .critical)
        XCTAssertEqual(StatLevel(celsius: 79.9), .normal)
        XCTAssertEqual(StatLevel(celsius: 80), .warning)
        XCTAssertEqual(StatLevel(celsius: 95), .critical)
    }

    func testLevelHoldsForFiveSeconds() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var hold = LevelHold()
        XCTAssertEqual(hold.update(.critical, at: t0), .normal)
        XCTAssertEqual(hold.update(.critical, at: t0 + 4.9), .normal)
        XCTAssertEqual(hold.update(.critical, at: t0 + 5), .critical)
        // A short dip doesn't flash back.
        XCTAssertEqual(hold.update(.normal, at: t0 + 6), .critical)
        XCTAssertEqual(hold.update(.critical, at: t0 + 8), .critical)
        // A new level restarts the wait.
        XCTAssertEqual(hold.update(.warning, at: t0 + 10), .critical)
        XCTAssertEqual(hold.update(.normal, at: t0 + 12), .critical)
        XCTAssertEqual(hold.update(.normal, at: t0 + 16.9), .critical)
        XCTAssertEqual(hold.update(.normal, at: t0 + 17), .normal)
    }

    func testFanFraction() {
        XCTAssertEqual(FanSample(rpm: 0, min: 2317, max: 7826).fraction, 0)
        XCTAssertEqual(FanSample(rpm: 3913, min: 2317, max: 7826).fraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(FanSample(rpm: 9000, min: 2317, max: 7826).fraction, 1)
    }

    // MARK: - Menu bar

    private func snapshot() -> MacStatsSnapshot {
        var s = MacStatsSnapshot()
        s.cpu = CPUSample(cores: [0.5, 0.5, 0.1, 0.1], efficiencyCount: 2, user: 0.2, system: 0.1)
        s.gpu = GPUSample(utilization: 0.3, memoryInUse: 0)
        s.memory = MemorySample(total: 100, pageSize: 1, anonymous: 60, purgeable: 0, wired: 0, compressor: 0, swapUsed: 0, pressure: .normal)
        s.systemWatts = 9.4
        s.thermal.cpuAverage = 41
        s.thermal.cpuHottest = 49
        s.fans = [FanSample(rpm: 0, min: 2317, max: 7826), FanSample(rpm: 0, min: 2317, max: 7826)]
        return s
    }

    func testMenuBarShowsEverythingByDefault() {
        let c = MacStatsMenuBarContent.make(snapshot(), levels: [.performance: .warning], temperatureLevel: .normal,
                                            fahrenheit: true, on: { _ in true }, source: .cpuAverage)
        XCTAssertEqual(c.temperature?.text, "106°")
        XCTAssertEqual(c.power?.text, "9 W")
        XCTAssertEqual(c.fan?.text, "Off")
        XCTAssertEqual(c.bars.map(\.part), [.efficiency, .performance, .gpu, .memory])
        XCTAssertEqual(c.bars.map(\.value), [0.5, 0.1, 0.3, 0.6])
        XCTAssertEqual(c.bars[1].level, .warning)
        XCTAssertEqual(c.fan?.unit, "fans")
        XCTAssertEqual(c.spoken, "Efficiency cores 50%, Performance cores 10%, GPU 30%, Memory 60%, Temperature 106°, Power 9 W, Fans off")
    }

    func testMenuBarFollowsTheSwitches() {
        let off: Set<String> = [MacStatsSettings.gpu, MacStatsSettings.power]
        let c = MacStatsMenuBarContent.make(snapshot(), levels: [:], temperatureLevel: .normal, fahrenheit: false,
                                            on: { !off.contains($0) }, source: .cpuHottest)
        XCTAssertEqual(c.temperature?.text, "49°")
        XCTAssertNil(c.power)
        XCTAssertEqual(c.bars.map(\.part), [.efficiency, .performance, .memory])

        let none = MacStatsMenuBarContent.make(snapshot(), levels: [:], temperatureLevel: .normal, fahrenheit: false,
                                               on: { $0 != MacStatsSettings.meters && $0 != MacStatsSettings.readouts })
        XCTAssertTrue(none.isEmpty)
    }

    func testMenuBarFanShareAndHeld() {
        var s = snapshot()
        s.fans = [FanSample(rpm: 2400, min: 2317, max: 7826), FanSample(rpm: 3913, min: 2317, max: 7826)]
        s.fansHeld = true
        let c = MacStatsMenuBarContent.make(s, levels: [:], temperatureLevel: .normal, fahrenheit: false, on: { _ in true })
        XCTAssertEqual(c.fan?.text, "3.9k")
        XCTAssertEqual(c.fan?.unit, "manual")
        XCTAssertTrue(c.fansHeld)
        XCTAssertEqual(MacStatsMenuBarContent.rpm(842), "840")
        XCTAssertEqual(MacStatsMenuBarContent.rpm(7826), "7.8k")
    }

    func testMenuBarWithoutEfficiencyCores() {
        var s = snapshot()
        s.cpu = CPUSample(cores: [0.4, 0.4], efficiencyCount: 0, user: 0.3, system: 0.1)
        let c = MacStatsMenuBarContent.make(s, levels: [:], temperatureLevel: .normal, fahrenheit: false, on: { _ in true })
        XCTAssertEqual(c.bars.map(\.part), [.performance, .gpu, .memory])
    }
}
