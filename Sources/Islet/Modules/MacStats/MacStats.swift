import Foundation
import Observation

/// One reading of everything Mac Stats shows (DESIGN.md "Mac Stats (1.7)"). Anything a reader couldn't get is nil.
struct MacStatsSnapshot: Sendable, Equatable {
    var date = Date.distantPast
    var cpu: CPUSample?
    var gpu: GPUSample?
    var memory: MemorySample?
    /// The whole Mac's draw (SMC `PSTR`, as the battery stats show).
    var systemWatts: Double?
    var energy: EnergySample?
    var thermal = ThermalSample()
    var fans: [FanSample] = []
    /// The fans are being held by fan control (`Ftst` = 1).
    var fansHeld = false
    /// Only while a page that lists them is open.
    var topCPU: [ProcessUse] = []
    var topMemory: [ProcessUse] = []
    var topGPU: [ProcessUse] = []

    /// The faster fan, for the menu bar.
    var fastestFan: FanSample? { fans.max { $0.rpm < $1.rpm } }
}

/// What the graphs need from each reading, kept for 10 minutes.
struct MacStatsPoint: Sendable, Equatable {
    var date: Date
    var efficiency: Double
    var performance: Double
    var user: Double
    var system: Double
    var gpu: Double
    var memoryFraction: Double
    var memoryPressure: MemoryPressure
    var watts: Double?

    init?(_ s: MacStatsSnapshot) {
        guard let cpu = s.cpu else { return nil }
        date = s.date
        efficiency = cpu.efficiency
        performance = cpu.performance
        user = cpu.user
        system = cpu.system
        gpu = s.gpu?.utilization ?? 0
        memoryFraction = s.memory?.fraction ?? 0
        memoryPressure = s.memory?.pressure ?? .normal
        watts = s.systemWatts
    }
}

/// Owns the readers (they keep their last reading to work out rates) and reads them off the main thread.
actor MacStatsSampler {
    private let cpu = CPUReader()
    private let gpu = GPUReader()
    private let energy = EnergyReader()
    private let thermal = ThermalReader()

    func sample(processes: Bool) -> MacStatsSnapshot {
        var s = MacStatsSnapshot()
        s.date = Date()
        s.cpu = cpu.sample()
        s.gpu = GPUReader.read()
        s.memory = MemorySample.read()
        s.systemWatts = SMCSensors.power()?.system
        s.energy = energy.sample()
        (s.thermal, s.fans, s.fansHeld) = thermal.sample()
        if processes {
            (s.topCPU, s.topMemory) = ProcessReader.read()
            s.topGPU = Array(gpu.processes().prefix(5))
        }
        return s
    }
}

/// Mac Stats' live figures and their last 10 minutes. Reads every `interval` while started, and nothing otherwise.
@MainActor @Observable
final class MacStats {
    static let shared = MacStats()

    private(set) var snapshot = MacStatsSnapshot()
    private(set) var history: [MacStatsPoint] = []
    /// Settings > Mac Stats > "Update every".
    var interval: Duration = .seconds(2)
    /// Set while a page that lists the busiest apps is open: running `ps` every time otherwise would be waste.
    var wantsProcesses = false {
        didSet { if wantsProcesses && !oldValue { refreshSoon() } }
    }

    static let historySpan: TimeInterval = 10 * 60

    @ObservationIgnored private let sampler = MacStatsSampler()
    @ObservationIgnored private var task: Task<Void, Never>?

    var running: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.read()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    /// Stops reading and forgets the history, as when Mac Stats is turned off.
    func stop() {
        task?.cancel()
        task = nil
        history = []
    }

    private func read() async {
        let s = await sampler.sample(processes: wantsProcesses)
        guard task != nil else { return }
        snapshot = s
        if let point = MacStatsPoint(s) {
            history.append(point)
            let cutoff = s.date.addingTimeInterval(-Self.historySpan)
            if let first = history.firstIndex(where: { $0.date >= cutoff }), first > 0 { history.removeFirst(first) }
        }
    }

    /// Fills the app lists straight away when a page opens, instead of waiting for the next reading.
    private func refreshSoon() {
        guard task != nil else { return }
        Task { [weak self] in await self?.read() }
    }

    /// When the Mac started, for "Up 6 days, 10 hr".
    static let bootDate: Date? = {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
    }()
}

// MARK: - Warnings

/// How worried a figure should look: the menu bar's own colour, yellow or red (DESIGN.md "Mac Stats (1.7)", Colours).
enum StatLevel: Int, Sendable, Comparable {
    case normal, warning, critical

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// CPU core groups and the GPU: above 70% and above 90%.
    init(load: Double) { self = load > 0.9 ? .critical : load > 0.7 ? .warning : .normal }

    /// From 80 °C and from 95 °C.
    init(celsius: Double) { self = celsius >= 95 ? .critical : celsius >= 80 ? .warning : .normal }

    init(_ pressure: MemoryPressure) {
        switch pressure {
        case .normal: self = .normal
        case .warning: self = .warning
        case .critical: self = .critical
        }
    }
}

/// Holds a level until a new one has lasted `hold` seconds, so a short spike (or dip) doesn't flash.
struct LevelHold: Sendable, Equatable {
    var hold: TimeInterval = 5
    private(set) var level: StatLevel = .normal
    private var pending: StatLevel?
    private var since: Date?

    init(hold: TimeInterval = 5) { self.hold = hold }

    @discardableResult
    mutating func update(_ raw: StatLevel, at now: Date) -> StatLevel {
        if raw == level {
            pending = nil
            since = nil
        } else if raw == pending, let since {
            if now.timeIntervalSince(since) >= hold {
                level = raw
                pending = nil
                self.since = nil
            }
        } else {
            pending = raw
            since = now
        }
        return level
    }
}
