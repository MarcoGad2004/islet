import Darwin
import Foundation
import IOKit

// The readers behind Mac Stats (DESIGN.md "Mac Stats (1.7)", RESEARCH.md "Mac Stats"). None needs any rights. The
// classes keep the previous reading to work out rates, so each belongs to one owner (`MacStatsSampler`).

// MARK: - CPU

struct CPUSample: Sendable, Equatable {
    /// Each core's busy share, 0...1, in the order the kernel lists them: efficiency cores first (checked on an M4 Pro).
    var cores: [Double]
    var efficiencyCount: Int
    var user: Double
    var system: Double

    var total: Double { user + system }
    var efficiency: Double { Self.mean(cores.prefix(efficiencyCount)) }
    var performance: Double { Self.mean(cores.dropFirst(efficiencyCount)) }

    private static func mean(_ xs: some Collection<Double>) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
}

final class CPUReader {
    /// User, system, idle and nice ticks per core.
    typealias Ticks = [[UInt64]]
    let efficiencyCount = CPUReader.efficiencyCores()
    private var last: Ticks?

    func sample() -> CPUSample? {
        guard let now = Self.ticks() else { return nil }
        defer { last = now }
        guard let last else { return nil }
        return Self.usage(from: last, to: now, efficiencyCount: efficiencyCount)
    }

    /// The busy shares between two readings. Nice time counts as user time, as Activity Monitor does.
    static func usage(from a: Ticks, to b: Ticks, efficiencyCount: Int) -> CPUSample? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var cores: [Double] = []
        var user: UInt64 = 0, system: UInt64 = 0, all: UInt64 = 0
        for (x, y) in zip(a, b) {
            guard x.count == 4, y.count == 4 else { return nil }
            let d = (0..<4).map { y[$0] >= x[$0] ? y[$0] - x[$0] : 0 }
            let total = d.reduce(0, +)
            cores.append(total == 0 ? 0 : Double(d[0] + d[1] + d[3]) / Double(total))
            user += d[0] + d[3]
            system += d[1]
            all += total
        }
        guard all > 0 else { return nil }
        return CPUSample(cores: cores, efficiencyCount: min(efficiencyCount, cores.count),
                         user: Double(user) / Double(all), system: Double(system) / Double(all))
    }

    private static func ticks() -> Ticks? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            [CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE].map {
                UInt64(UInt32(bitPattern: info[core * states + Int($0)]))
            }
        }
    }

    /// How many efficiency cores: the `hw.perflevel` named "Efficiency"; none on a Mac with one kind of core.
    private static func efficiencyCores() -> Int {
        let levels = sysctlInt("hw.nperflevels") ?? 1
        for level in 0..<max(levels, 0) where sysctlString("hw.perflevel\(level).name") == "Efficiency" {
            return sysctlInt("hw.perflevel\(level).logicalcpu") ?? 0
        }
        return 0
    }
}

// MARK: - Memory

enum MemoryPressure: Int, Sendable, Comparable {
    case normal, warning, critical

    /// From `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    init(kernelLevel: Int) { self = kernelLevel >= 4 ? .critical : kernelLevel >= 2 ? .warning : .normal }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

struct MemorySample: Sendable, Equatable {
    var total: UInt64
    /// What Activity Monitor calls App Memory: anonymous pages that can't be purged.
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var swapUsed: UInt64
    var pressure: MemoryPressure

    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used ? total - used : 0 }
    var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    /// Activity Monitor's sums, from page counts.
    init(total: UInt64, pageSize: UInt64, anonymous: UInt64, purgeable: UInt64, wired: UInt64, compressor: UInt64,
         swapUsed: UInt64, pressure: MemoryPressure) {
        self.total = total
        app = (anonymous > purgeable ? anonymous - purgeable : 0) * pageSize
        self.wired = wired * pageSize
        compressed = compressor * pageSize
        self.swapUsed = swapUsed
        self.pressure = pressure
    }

    static func read() -> MemorySample? {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size) }
        }
        guard r == KERN_SUCCESS, let total = sysctlInt("hw.memsize") else { return nil }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0
        return MemorySample(total: UInt64(total), pageSize: UInt64(getpagesize()),
                            anonymous: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                            wired: UInt64(stats.wire_count), compressor: UInt64(stats.compressor_page_count),
                            swapUsed: swapUsed,
                            pressure: MemoryPressure(kernelLevel: sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1))
    }
}

// MARK: - GPU

struct GPUSample: Sendable, Equatable {
    /// 0...1.
    var utilization: Double
    var memoryInUse: UInt64
}

/// What one process is using: a share (CPU and GPU, where 1 is one core or the whole GPU) or bytes (memory).
struct ProcessUse: Sendable, Equatable, Identifiable {
    var pid: pid_t
    var name: String
    var value: Double
    var id: pid_t { pid }
}

final class GPUReader {
    private var lastTimes: [pid_t: UInt64] = [:]
    private var lastDate: Date?

    /// The GPU's own figures, from its `PerformanceStatistics`.
    static func read() -> GPUSample? {
        var found: [String: Any]?
        for entry in acceleratorEntries() {
            if found == nil { found = property(entry, "PerformanceStatistics") as? [String: Any] }
            IOObjectRelease(entry)
        }
        guard let stats = found else { return nil }
        let util = (stats["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0
        let memory = (stats["In use system memory"] as? NSNumber)?.uint64Value ?? 0
        return GPUSample(utilization: min(max(util / 100, 0), 1), memoryInUse: memory)
    }

    /// Each process's share of the GPU since the last call, from the GPU time its connections have used
    /// (`AGXDeviceUserClient` `AppUsage`). Only processes that used it.
    func processes() -> [ProcessUse] {
        var times: [pid_t: UInt64] = [:]
        var names: [pid_t: String] = [:]
        for entry in Self.acceleratorEntries() {
            var iterator: io_iterator_t = 0
            if IORegistryEntryCreateIterator(entry, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS {
                while case let child = IOIteratorNext(iterator), child != 0 {
                    defer { IOObjectRelease(child) }
                    guard let creator = Self.property(child, "IOUserClientCreator") as? String,
                          let (pid, name) = Self.parseCreator(creator) else { continue }
                    let usage = Self.property(child, "AppUsage") as? [[String: Any]] ?? []
                    let ns = usage.reduce(UInt64(0)) { $0 + ((($1["accumulatedGPUTime"]) as? NSNumber)?.uint64Value ?? 0) }
                    times[pid, default: 0] += ns
                    names[pid] = name
                }
                IOObjectRelease(iterator)
            }
            IOObjectRelease(entry)
        }
        let now = Date()
        defer { lastTimes = times; lastDate = now }
        guard let lastDate, now.timeIntervalSince(lastDate) > 0.2 else { return [] }
        let span = now.timeIntervalSince(lastDate) * 1e9
        return times.compactMap { pid, ns in
            guard let before = lastTimes[pid], ns > before else { return nil }
            return ProcessUse(pid: pid, name: names[pid] ?? "\(pid)", value: Double(ns - before) / span)
        }.sorted { $0.value > $1.value }
    }

    /// "pid 616, WindowServer" (the name is cut at 16 characters).
    static func parseCreator(_ s: String) -> (pid_t, String)? {
        guard s.hasPrefix("pid ") else { return nil }
        let parts = s.dropFirst(4).split(separator: ",", maxSplits: 1)
        guard let pid = pid_t(parts.first ?? "") else { return nil }
        return (pid, parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "\(pid)")
    }

    private static func acceleratorEntries() -> [io_object_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var out: [io_object_t] = []
        while case let e = IOIteratorNext(iterator), e != 0 { out.append(e) }
        return out
    }

    private static func property(_ entry: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

// MARK: - Energy (IOReport)

struct EnergySample: Sendable, Equatable {
    var cpu: Double
    var gpu: Double
    var neuralEngine: Double
}

@_silgen_name("IOReportCopyChannelsInGroup")
private func IOReportCopyChannelsInGroup(_ group: CFString?, _ subgroup: CFString?, _ a: UInt64, _ b: UInt64, _ c: UInt64) -> Unmanaged<CFMutableDictionary>?
@_silgen_name("IOReportCreateSubscription")
private func IOReportCreateSubscription(_ a: UnsafeMutableRawPointer?, _ channels: CFMutableDictionary,
                                        _ subscribed: UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>,
                                        _ id: UInt64, _ b: CFTypeRef?) -> OpaquePointer?
@_silgen_name("IOReportCreateSamples")
private func IOReportCreateSamples(_ subscription: OpaquePointer, _ channels: CFMutableDictionary, _ b: CFTypeRef?) -> Unmanaged<CFDictionary>?
@_silgen_name("IOReportCreateSamplesDelta")
private func IOReportCreateSamplesDelta(_ a: CFDictionary, _ b: CFDictionary, _ c: CFTypeRef?) -> Unmanaged<CFDictionary>?
@_silgen_name("IOReportSimpleGetIntegerValue")
private func IOReportSimpleGetIntegerValue(_ item: CFDictionary, _ index: Int32) -> Int64
@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ item: CFDictionary) -> Unmanaged<CFString>?
@_silgen_name("IOReportChannelGetUnitLabel")
private func IOReportChannelGetUnitLabel(_ item: CFDictionary) -> Unmanaged<CFString>?

/// CPU, GPU and Neural Engine watts from IOReport's "Energy Model" group (no root needed, unlike `powermetrics`).
/// CPU energy only moves about once a second, so read it no more often than every 2 s.
final class EnergyReader {
    private var subscription: OpaquePointer?
    private var channels: CFMutableDictionary?
    private var last: (CFDictionary, Date)?

    init() {
        guard let group = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return }
        var subscribed: Unmanaged<CFMutableDictionary>?
        subscription = IOReportCreateSubscription(nil, group, &subscribed, 0, nil)
        channels = subscribed?.takeRetainedValue()
    }

    func sample() -> EnergySample? {
        guard let subscription, let channels,
              let now = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue() else { return nil }
        let date = Date()
        defer { last = (now, date) }
        guard let (before, then) = last, date.timeIntervalSince(then) > 0.5,
              let delta = IOReportCreateSamplesDelta(before, now, nil)?.takeRetainedValue() as? [String: Any],
              let items = delta["IOReportChannels"] as? [CFDictionary] else { return nil }
        var joules: [String: Double] = [:]
        for item in items {
            guard let name = IOReportChannelGetChannelName(item)?.takeUnretainedValue() as String?,
                  ["CPU Energy", "GPU Energy", "ANE"].contains(name) else { continue }
            let unit = (IOReportChannelGetUnitLabel(item)?.takeUnretainedValue() as String? ?? "").trimmingCharacters(in: .whitespaces)
            joules[name] = Self.joules(IOReportSimpleGetIntegerValue(item, 0), unit: unit)
        }
        let seconds = date.timeIntervalSince(then)
        return EnergySample(cpu: (joules["CPU Energy"] ?? 0) / seconds, gpu: (joules["GPU Energy"] ?? 0) / seconds,
                            neuralEngine: (joules["ANE"] ?? 0) / seconds)
    }

    static func joules(_ value: Int64, unit: String) -> Double {
        let v = Double(max(value, 0))
        switch unit {
        case "mJ": return v / 1e3
        case "uJ", "µJ": return v / 1e6
        case "nJ": return v / 1e9
        default: return 0
        }
    }
}

// MARK: - Temperatures and fans (SMC)

struct ThermalSample: Sendable, Equatable {
    var cpuAverage: Double?
    var cpuHottest: Double?
    var gpuAverage: Double?
    var gpuHottest: Double?
    var ssd: Double?
}

struct FanSample: Sendable, Equatable {
    var rpm: Double
    var min: Double
    var max: Double
    /// The faster fan's share of its range for the menu bar: 0 when stopped.
    var fraction: Double { max > 0 ? Swift.min(Swift.max(rpm / max, 0), 1) : 0 }
}

final class ThermalReader {
    /// Which SMC keys are which: found once by listing them all (RESEARCH.md "Mac Stats"). Which CPU sensors make the
    /// fairest "CPU" figure is still to be compared with iStat Menus; for now every `Tp`/`Te` key that reads sensibly.
    private lazy var keys: (cpu: [String], gpu: [String], ssd: [String]) = {
        let all = SMCSensors.allKeys().filter { $0.hasPrefix("T") }
        return (all.filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }, all.filter { $0.hasPrefix("Tg") },
                all.filter { $0 == "TH0x" })
    }()

    private lazy var fanCount: Int = Int(SMCSensors.values(["FNum"])["FNum"] ?? 0)

    func sample() -> (ThermalSample, [FanSample], fansHeld: Bool) {
        let fanKeys = (0..<fanCount).flatMap { ["F\($0)Ac", "F\($0)Mn", "F\($0)Mx"] } + ["Ftst"]
        let v = SMCSensors.values(keys.cpu + keys.gpu + keys.ssd + fanKeys)
        let thermal = ThermalSample(cpuAverage: Self.mean(keys.cpu, v), cpuHottest: Self.hottest(keys.cpu, v),
                                    gpuAverage: Self.mean(keys.gpu, v), gpuHottest: Self.hottest(keys.gpu, v),
                                    ssd: Self.mean(keys.ssd, v))
        let fans = (0..<fanCount).compactMap { i -> FanSample? in
            guard let rpm = v["F\(i)Ac"] else { return nil }
            return FanSample(rpm: max(rpm, 0), min: v["F\(i)Mn"] ?? 0, max: v["F\(i)Mx"] ?? 0)
        }
        return (thermal, fans, (v["Ftst"] ?? 0) == 1)
    }

    /// Readings that make sense: some keys read a few degrees (unused) or nonsense.
    static func sensible(_ keys: [String], _ v: [String: Double]) -> [Double] {
        keys.compactMap { v[$0] }.filter { $0 >= 10 && $0 < 130 }
    }

    static func mean(_ keys: [String], _ v: [String: Double]) -> Double? {
        let xs = sensible(keys, v)
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    static func hottest(_ keys: [String], _ v: [String: Double]) -> Double? { sensible(keys, v).max() }
}

// MARK: - Processes

/// The processes using the most CPU and memory. `ps` sees every process; a normal app's `proc_pid_rusage` can't read
/// root's (WindowServer, launchd), so `ps` gives the CPU and the list, and the memory figure is the footprint (as
/// Activity Monitor shows) where it can be read, else the resident size.
enum ProcessReader {
    struct Row: Equatable { var pid: pid_t; var cpu: Double; var residentKB: UInt64; var name: String }

    static func read(limit: Int = 5) -> (cpu: [ProcessUse], memory: [ProcessUse]) {
        let rows = parse(runPS())
        let cpu = rows.sorted { $0.cpu > $1.cpu }.prefix(limit)
            .map { ProcessUse(pid: $0.pid, name: $0.name, value: $0.cpu / 100) }
        let memory = rows.map { r in ProcessUse(pid: r.pid, name: r.name, value: Double(footprint(r.pid) ?? r.residentKB * 1024)) }
            .sorted { $0.value > $1.value }.prefix(limit)
        return (Array(cpu), Array(memory))
    }

    /// `ps -axo pid=,%cpu=,rss=,comm=` lines: the command is a path, possibly with spaces.
    static func parse(_ text: String) -> [Row] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard f.count == 4, let pid = pid_t(f[0]), let cpu = Double(f[1]), let rss = UInt64(f[2]) else { return nil }
            return Row(pid: pid, cpu: cpu, residentKB: rss, name: (String(f[3]) as NSString).lastPathComponent)
        }
    }

    private static func runPS() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,%cpu=,rss=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return r == 0 ? info.ri_phys_footprint : nil
    }
}

// MARK: - sysctl

func sysctlInt(_ name: String) -> Int? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    // Some are 32-bit: the bytes land at the low end.
    return size == 4 ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
