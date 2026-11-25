import Foundation
import IOKit
import IOKit.ps

/// Battery and charger state from IOKit, driven by notifications (no polling). The battery driver's own messages come
/// first: powerd republishes the power-source list a second or two after a charger goes in, so plugging in is read
/// from the battery's registry entry the moment the driver says something changed.
@MainActor @Observable
final class PowerMonitor {
    struct State: Equatable {
        var percent = 100
        var onAC = false
        var charging = false
        var charged = false
        var minutesToFull: Int?
        var minutesToEmpty: Int?
        var hasBattery = true
    }

    private(set) var state = State() {
        didSet { if state != oldValue { history.record(state) } }
    }
    /// The charge over the last day, for the battery stats.
    let history = BatteryHistory()

    /// The battery page's numbers, read from the battery's registry entry while the page is open.
    struct Details: Equatable {
        /// Full-charge capacity as a share of the design capacity (what System Settings calls Maximum Capacity).
        var health: Int?
        var cycles: Int?
        var designCycles: Int?
        var currentMAh: Int?
        var fullMAh: Int?
        var voltage: Double?
        /// Into the battery (+, charging) or out of it (-), in watts.
        var batteryWatts: Double?
        /// What the whole Mac is drawing right now, in watts.
        var systemWatts: Double?
        var adapterWatts: Int?
        var adapterName: String?
        var lowPower = false
        /// The charge limit set in System Settings > Battery (macOS 26+), when it's below 100%.
        var chargeLimit: Int?
        /// The battery's temperature in °C, from the SMC.
        var temperature: Double?
        /// What the charger is delivering right now, in watts.
        var adapterInWatts: Double?

        /// Energy in the battery now, and when full, in watt-hours.
        var storedWh: Double? { zip(currentMAh, voltage).map { Double($0) * $1 / 1000 } }
        var fullWh: Double? { zip(fullMAh, voltage).map { Double($0) * $1 / 1000 } }
    }

    private(set) var details = Details()
    /// Maximum capacity and condition exactly as System Settings shows them. macOS works these out privately (its
    /// 97% isn't any ratio in the registry), so they come from `system_profiler` once per page open.
    private(set) var reportedHealth: (percent: Int, condition: String)?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored var onEvent: ((ChargeEvent) -> Void)?
    /// The shown charger event with what came in after it (the time to full, which powerd works out a moment later).
    @ObservationIgnored var onEventUpdate: ((ChargeEvent) -> Void)?
    @ObservationIgnored private var batteryNotify: IONotificationPortRef?
    @ObservationIgnored private var batteryInterest: io_object_t = 0
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var delayed: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var followUp: Task<Void, Never>?

    func start() {
        state = Self.read()
        history.record(state)
        started = true
        // A sample every few minutes while nothing changes, so the chart's line keeps going.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(BatteryHistory.interval))
                guard let self else { return }
                self.history.record(Self.read())
            }
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.changed() }
        }, ctx)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        watchBattery()
    }

    /// The battery driver messages its clients whenever its status changes (a charger in or out among them), before
    /// powerd has republished anything.
    private func watchBattery() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        defer { IOObjectRelease(service) }
        batteryNotify = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { ctx, _, _, _ in
            guard let ctx else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.changed() }
        }, ctx, &batteryInterest)
    }

    func refresh() { state = Self.read() }

    /// Who wants the live numbers now (the stats panel, the island's battery page): they run while any does, so one
    /// closing doesn't freeze the other's.
    @ObservationIgnored private var detailOwners: Set<String> = []
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var healthAttempt = Date.distantPast
    @ObservationIgnored private var healthRead = Date.distantPast
    /// System Settings' Maximum Capacity moves over weeks: read it again after this long.
    private static let healthMaxAge: TimeInterval = 6 * 3600

    /// While the battery page or the stats are open, re-read everything every second so the power draw stays live.
    func watchDetails(_ on: Bool, owner: String = "island") {
        let was = !detailOwners.isEmpty
        if on { detailOwners.insert(owner) } else { detailOwners.remove(owner) }
        let now = !detailOwners.isEmpty
        if !now {
            detailsTask?.cancel()
            detailsTask = nil
            return
        }
        guard on else { return }
        let fresh = Self.readDetails()
        if fresh != details { details = fresh }
        readHealthIfStale()
        guard !was || detailsTask == nil else { return }
        detailsTask?.cancel()
        detailsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                // Set only what changed: an equal value still wakes everything that watches it.
                let d = Self.readDetails()
                if d != self.details { self.details = d }
                let s = Self.read()
                if s != self.state { self.state = s }
            }
        }
    }

    /// `system_profiler` takes a second or two of CPU: not on every opening, and not twice at once.
    private func readHealthIfStale() {
        let now = Date()
        guard healthTask == nil, now.timeIntervalSince(healthAttempt) > 600,
              reportedHealth == nil || now.timeIntervalSince(healthRead) > Self.healthMaxAge else { return }
        healthAttempt = now
        healthTask = Task { [weak self] in
            let h = await Self.readReportedHealth()
            guard let self else { return }
            healthTask = nil
            if let h {
                reportedHealth = h
                healthRead = Date()
            }
        }
    }

    /// The charge limit changes only when the owner edits it in System Settings: read the file now and then, not
    /// every second.
    private static var chargeLimitCache: (at: Date, value: Int?)?
    private static func cachedChargeLimit() -> Int? {
        if let c = chargeLimitCache, Date().timeIntervalSince(c.at) < 20 { return c.value }
        let v = readChargeLimit()
        chargeLimitCache = (Date(), v)
        return v
    }

    /// The battery's temperature moves over minutes: read it every so often.
    private static var temperatureCache: (at: Date, value: Double?)?
    private static func cachedTemperature() -> Double? {
        if let c = temperatureCache, Date().timeIntervalSince(c.at) < 15 { return c.value }
        let v = SMCSensors.temperature()
        temperatureCache = (Date(), v)
        return v
    }

    /// powerd keeps the charging policies in a world-readable file: an archived list whose `manualChargeLimit` entry
    /// carries the limit as `soclimit`. Only System Settings can change it (a private, entitled call), so this is
    /// read-only; the battery page links to Battery settings for changing it.
    private static func readChargeLimit() -> Int? {
        guard let file = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.powerd.charging.plist"),
              let blob = file["policies"] as? Data,
              let archive = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any],
              let objects = archive["$objects"] as? [Any] else { return nil }
        for case let policy as [String: Any] in objects {
            guard let limit = (policy["soclimit"] as? NSNumber)?.intValue, limit > 0, limit < 100,
                  (policy["terminated"] as? Bool) != true else { continue }
            // The reason is stored by reference; accept the manual limit (or an unlabelled one).
            if let ref = policy["reason"], let i = Self.uid(ref), i < objects.count,
               let reason = objects[i] as? String, reason != "manualChargeLimit" { continue }
            return limit
        }
        return nil
    }

    /// The index inside an archive's `CF$UID` reference.
    private static func uid(_ ref: Any) -> Int? {
        if let d = ref as? [String: Any], let n = d["CF$UID"] as? NSNumber { return n.intValue }
        // Bridged CFKeyedArchiverUID: its description reads "<CFKeyedArchiverUID ...>{value = 3}".
        let text = String(describing: ref)
        guard let r = text.range(of: "value = ") else { return nil }
        return Int(text[r.upperBound...].prefix { $0.isNumber })
    }

    private nonisolated static func readReportedHealth() async -> (percent: Int, condition: String)? {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPPowerDataType", "-json"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["SPPowerDataType"] as? [[String: Any]] else { return nil }
            for item in items {
                guard let h = item["sppower_battery_health_info"] as? [String: Any],
                      let text = h["sppower_battery_health_maximum_capacity"] as? String,
                      let percent = Int(text.filter(\.isNumber)) else { continue }
                let raw = h["sppower_battery_health"] as? String ?? ""
                return (percent, raw == "Good" || raw.isEmpty ? "Normal" : raw)
            }
            return nil
        }.value
    }

    private static func readDetails() -> Details {
        var d = Details()
        d.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        d.chargeLimit = cachedChargeLimit()
        d.temperature = cachedTemperature()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return d }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let p = props?.takeRetainedValue() as? [String: Any] else { return d }
        let data = p["BatteryData"] as? [String: Any] ?? [:]
        // Signed values (current flowing out) come through as huge unsigned numbers; Int64 wraps them back.
        func num(_ k: String) -> Int64? { ((p[k] ?? data[k]) as? NSNumber)?.int64Value }

        let design = num("DesignCapacity")
        let nominal = num("NominalChargeCapacity") ?? num("AppleRawMaxCapacity")
        if let design, let nominal, design > 0 { d.health = min(100, Int((Double(nominal) / Double(design) * 100).rounded())) }
        d.cycles = num("CycleCount").map(Int.init)
        d.designCycles = num("DesignCycleCount9C").map(Int.init)
        d.currentMAh = num("AppleRawCurrentCapacity").map(Int.init)
        d.fullMAh = num("AppleRawMaxCapacity").map(Int.init)
        if let v = num("Voltage"), v > 0 { d.voltage = Double(v) / 1000 }
        if let v = num("Voltage"), let a = num("Amperage"), a != 0 { d.batteryWatts = Double(v) * Double(a) / 1_000_000 }
        let telemetry = p["PowerTelemetryData"] as? [String: Any] ?? [:]
        if let load = (telemetry["SystemLoad"] as? NSNumber)?.int64Value, load > 0 { d.systemWatts = Double(load) / 1000 }
        if let input = (telemetry["SystemPowerIn"] as? NSNumber)?.int64Value, input > 0 { d.adapterInWatts = Double(input) / 1000 }
        else if let b = d.batteryWatts, b < 0 { d.systemWatts = -b }
        // The registry's numbers are up to 30 s old; the SMC's are live.
        if let live = SMCSensors.power() {
            d.systemWatts = live.system
            if let b = live.battery { d.batteryWatts = b }
            if let c = live.chargerIn { d.adapterInWatts = c > 0.1 ? c : nil }
        }
        if (p["ExternalConnected"] as? Bool) == true, let adapter = p["AdapterDetails"] as? [String: Any] {
            d.adapterWatts = (adapter["Watts"] as? NSNumber)?.intValue
            d.adapterName = (adapter["Name"] as? String)?.trimmingCharacters(in: .whitespaces)
        }
        return d
    }

    private func changed() {
        let old = state
        let new = Self.read()
        if new != state { state = new }
        // A charger in or out changes where the power goes at once, not on the next tick.
        if detailsTask != nil {
            let d = Self.readDetails()
            if d != details { details = d }
        }
        guard started, new.hasBattery else { return }

        // A charger in or out: nothing announces the moment charging actually starts (or stops), so look again every
        // second for a while; the menu bar battery's bolt follows within a second.
        if new.onAC != old.onAC {
            followUp?.cancel()
            followUp = Task { [weak self] in
                for _ in 0..<15 {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    let s = Self.read()
                    if s != self.state { self.state = s }
                }
            }
        }
        if new.onAC && !old.onAC {
            // Shown at once; the time to full is often unknown for a second or two after plugging in, so it's filled in
            // when it arrives.
            let event = new.charged ? ChargeEvent(kind: .full, percent: new.percent)
                                    : ChargeEvent(kind: .connected, percent: new.percent, minutesToFull: new.minutesToFull)
            onEvent?(event)
            delayed?.cancel()
            guard event.kind == .connected, event.minutesToFull == nil else { return }
            delayed = Task { [weak self] in
                for wait in [0.6, 0.8, 1.0] {
                    try? await Task.sleep(for: .seconds(wait))
                    guard let self, !Task.isCancelled, state.onAC else { return }
                    let s = Self.read()
                    state = s
                    if let m = s.minutesToFull {
                        onEventUpdate?(ChargeEvent(kind: .connected, percent: s.percent, minutesToFull: m))
                        return
                    }
                }
            }
        } else if new.onAC && new.charged && !old.charged {
            onEvent?(ChargeEvent(kind: .full, percent: new.percent))
        } else if !new.onAC && !new.charging {
            // Low battery only when not charging: once at 20% and once at 10%.
            for threshold in [20, 10] where old.percent > threshold && new.percent <= threshold {
                onEvent?(ChargeEvent(kind: .low, percent: new.percent))
                break
            }
        }
    }

    private static func read() -> State {
        var s = State()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { s.hasBattery = false; return s }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            s.percent = d[kIOPSCurrentCapacityKey] as? Int ?? 100
            s.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            s.charging = d[kIOPSIsChargingKey] as? Bool ?? false
            s.charged = (d[kIOPSIsChargedKey] as? Bool ?? false) || (s.onAC && s.percent >= 100)
            if let t = d[kIOPSTimeToFullChargeKey] as? Int, t > 0 { s.minutesToFull = t }
            if let t = d[kIOPSTimeToEmptyKey] as? Int, t > 0 { s.minutesToEmpty = t }
            // The driver knows about the charger, and whether it's charging, a second or two before powerd's list does.
            if let flags = batteryFlags() {
                if flags.external != s.onAC {
                    s.onAC = flags.external
                    if !flags.external { s.minutesToFull = nil }
                }
                s.charging = flags.external && flags.charging
                s.charged = s.onAC && (s.charged || flags.full || s.percent >= 100)
            }
            // The battery's flags refresh only every so often; the SMC's power figures are live. More coming in than
            // the Mac is using means the rest is going into the battery: it's charging, whatever the flags say yet.
            if s.onAC, !s.charging, let p = SMCSensors.power(), let input = p.chargerIn, input - p.system > 2 {
                s.charging = true
            }
            if s.charging { s.charged = false }
            return s
        }
        s.hasBattery = false
        return s
    }
}

/// The battery's own charger and charging flags, straight from its registry entry.
private func batteryFlags() -> (external: Bool, charging: Bool, full: Bool)? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    func flag(_ key: String) -> Bool? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }
    guard let external = flag("ExternalConnected") else { return nil }
    return (external, flag("IsCharging") ?? false, flag("FullyCharged") ?? false)
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
