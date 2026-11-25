import AppKit
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
    /// Only while a page that lists them is open: every process with some use, before `ProcessNames` groups them.
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

/// What a reading has to include beyond the basics: the menu bar needs only some of it, and the rest is read while the
/// panel is open (every extra reading is wake-ups and system calls every few seconds, all day).
struct MacStatsNeeds: Sendable, Equatable {
    /// Temperatures and fan speeds (the SMC's other ~50 keys).
    var thermal = false
    /// CPU, GPU and Neural Engine watts (IOReport).
    var energy = false
}

/// Owns the readers (they keep their last reading to work out rates) and reads them off the main thread.
actor MacStatsSampler {
    private let cpu = CPUReader()
    private let gpu = GPUReader()
    private let energy = EnergyReader()
    private let thermal = ThermalReader()

    func sample(processes: Bool, needs: MacStatsNeeds = MacStatsNeeds(thermal: true, energy: true)) -> MacStatsSnapshot {
        var s = MacStatsSnapshot()
        s.date = Date()
        s.cpu = cpu.sample()
        s.gpu = GPUReader.read()
        s.memory = MemorySample.read()
        // The power draw comes in the same SMC session as the temperatures and fans.
        let smc = thermal.sample(full: needs.thermal)
        s.systemWatts = smc.systemWatts
        (s.thermal, s.fans, s.fansHeld) = (smc.thermal, smc.fans, smc.fansHeld)
        if needs.energy {
            s.energy = energy.sample()
        } else {
            // Not measured meanwhile, so the next window starts fresh instead of spanning the time it was off.
            energy.reset()
        }
        if processes {
            (s.topCPU, s.topMemory) = ProcessReader.read()
            s.topGPU = gpu.processes()
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
    /// `history` in the charts' 5-second slots, worked out once a reading instead of by every chart on every redraw.
    private(set) var buckets: [MacStatsPoint] = []
    /// Settings > Mac Stats > "Update every".
    var interval: Duration = .seconds(2)
    /// Set while a page that lists the busiest apps is open: running `ps` every time otherwise would be waste.
    var wantsProcesses = false {
        didSet { if wantsProcesses && !oldValue { refreshSoon() } }
    }
    /// The stats panel is open: the readings only it shows (energy, and the temperatures and fans when the menu bar
    /// doesn't show them) are taken, and the charts' slots are worked out.
    var panelOpen = false {
        didSet {
            guard panelOpen != oldValue else { return }
            buckets = panelOpen ? ChartHistory.buckets(history) : []
        }
    }
    /// The menu bar item shows a temperature or the fan speed.
    var menuNeedsThermal = false

    static let historySpan: TimeInterval = 10 * 60
    /// The app lists are read no more often than this (seconds).
    static let processEvery: TimeInterval = 2
    @ObservationIgnored private var lastProcessRead = Date.distantPast

    @ObservationIgnored private let sampler = MacStatsSampler()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The display is asleep or the screen locked: nobody can see the readings, so none are taken.
    @ObservationIgnored private var displayAsleep = false
    @ObservationIgnored private var screenLocked = false
    private var paused: Bool { displayAsleep || screenLocked }

    var running: Bool { task != nil }

    init() {
        // The singleton lives as long as the app: nothing to remove.
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ change: @escaping @MainActor (MacStats) -> Void) {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let was = self.paused
                change(self)
                // Waking: a reading at once, not at the end of the long wait.
                if was && !self.paused { self.refreshSoon() }
            }
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.paused { await self.read() }
                // Asleep: look again rarely (waking up reads at once). Otherwise a little give lets the system run
                // this together with other wake-ups.
                let wait: Duration = self.paused ? .seconds(30) : self.interval
                try? await Task.sleep(for: wait, tolerance: .milliseconds(250))
            }
        }
    }

    /// Stops reading and forgets the history, as when Mac Stats is turned off.
    func stop() {
        task?.cancel()
        task = nil
        history = []
        buckets = []
    }

    private func read(processes: Bool? = nil) async {
        var processes = processes ?? wantsProcesses
        // `ps` and the lookups behind it cost more than the rest of a reading together: at the 1 s setting the app
        // lists update every other reading.
        if processes, !snapshot.topCPU.isEmpty, Date().timeIntervalSince(lastProcessRead) < Self.processEvery - 0.2 { processes = false }
        if processes { lastProcessRead = Date() }
        let needs = MacStatsNeeds(thermal: menuNeedsThermal || panelOpen, energy: panelOpen)
        var s = await sampler.sample(processes: processes, needs: needs)
        guard task != nil else { return }
        if processes {
            // Names and icons are looked up once and kept: done here, a page's first showing doesn't stall on them.
            _ = ProcessNames.group(s.topCPU)
            _ = ProcessNames.group(s.topMemory)
            _ = ProcessNames.group(s.topGPU)
        } else {
            // The lists from the last reading that had them, so a page shows them at once and updates them after.
            s.topCPU = snapshot.topCPU
            s.topMemory = snapshot.topMemory
            s.topGPU = snapshot.topGPU
        }
        snapshot = s
        if let point = MacStatsPoint(s) {
            history.append(point)
            let cutoff = s.date.addingTimeInterval(-Self.historySpan)
            if let first = history.firstIndex(where: { $0.date >= cutoff }), first > 0 { history.removeFirst(first) }
            // Only the open panel's charts use the slots.
            if panelOpen { buckets = ChartHistory.buckets(history) }
        }
    }

    /// One reading with the app lists as the panel opens, so they're there before a page is opened.
    func prefetchProcesses() {
        guard task != nil else { return }
        Task { [weak self] in await self?.read(processes: true) }
    }

    /// Fills the app lists straight away when a page opens, instead of waiting for the next reading.
    private func refreshSoon() {
        guard task != nil else { return }
        Task { [weak self] in await self?.read() }
    }

    /// When the Mac started, for "Up 6 days, 10 hr".
    nonisolated static let bootDate: Date? = {
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
