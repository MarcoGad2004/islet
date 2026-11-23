import Foundation

/// The charge over the last day, for the battery stats' chart, and when the charger last came out. Islet records a
/// sample whenever the charge or the charger changes and every few minutes in between, kept in Application Support.
/// The time Islet wasn't running is filled in from powerd's log (`pmset -g log`), which notes the charge at every
/// sleep, wake and power change.
@MainActor @Observable
final class BatteryHistory {
    struct Sample: Codable, Equatable {
        var time: Date
        var percent: Int
        var onAC: Bool
    }

    /// Oldest first, the last `keep` only.
    private(set) var samples: [Sample] = []
    /// When the Mac last went onto its battery; nil while it's on the charger, or when that isn't known.
    private(set) var unpluggedAt: Date?

    nonisolated static let keep: TimeInterval = 24 * 3600
    /// A sample at least this often while nothing changes, so the chart's line runs to now.
    nonisolated static let interval: TimeInterval = 5 * 60

    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var backfilled = false
    @ObservationIgnored private let file: URL?

    init(file: URL? = BatteryHistory.defaultFile) {
        self.file = file
        guard let file, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        samples = saved.samples
        unpluggedAt = saved.unpluggedAt
    }

    private struct Saved: Codable {
        var samples: [Sample]
        var unpluggedAt: Date?
    }

    nonisolated static var defaultFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Islet", isDirectory: true).appendingPathComponent("BatteryHistory.json")
    }

    /// The battery's state now. A new sample when the charge or the charger changed, or `interval` has passed.
    func record(_ state: PowerMonitor.State, at now: Date = Date()) {
        guard state.hasBattery else { return }
        let sample = Sample(time: now, percent: state.percent, onAC: state.onAC)
        let last = samples.last
        if state.onAC { unpluggedAt = nil } else if last?.onAC == true { unpluggedAt = now }
        guard last == nil || last!.percent != sample.percent || last!.onAC != sample.onAC
                || now.timeIntervalSince(last!.time) >= Self.interval else { return }
        samples.append(sample)
        trim(now)
        save(force: last?.onAC != sample.onAC)
    }

    /// The last `hours` of samples, with the charge now at the end so the line reaches the right edge.
    func recent(hours: Double, now: Date = Date(), current: PowerMonitor.State?) -> [Sample] {
        let start = now.addingTimeInterval(-hours * 3600)
        var out = samples.filter { $0.time >= start }
        // Carry the last charge before the window to its left edge.
        if let before = samples.last(where: { $0.time < start }) {
            out.insert(Sample(time: start, percent: before.percent, onAC: before.onAC), at: 0)
        }
        if let current, current.hasBattery { out.append(Sample(time: now, percent: current.percent, onAC: current.onAC)) }
        return out
    }

    /// Fill gaps (and the time since the charger came out) from powerd's log, once per launch and only when there is
    /// a gap: reading the log takes a few seconds of CPU, off the main thread.
    func backfillIfNeeded(now: Date = Date()) {
        guard !backfilled else { return }
        let gap = samples.last.map { now.timeIntervalSince($0.time) > Self.interval * 3 } ?? true
        let starts = samples.first.map { $0.time > now.addingTimeInterval(-12 * 3600) } ?? true
        guard gap || starts || (unpluggedAt == nil && samples.last?.onAC == false) else { return }
        backfilled = true
        Task { [weak self] in
            let logged = await Self.readLog()
            self?.merge(logged, now: Date())
        }
    }

    /// Log samples go where Islet has none of its own (more than `interval` from any of them).
    func merge(_ logged: [Sample], now: Date) {
        let start = now.addingTimeInterval(-Self.keep)
        let own = samples
        let extra = logged.filter { l in
            l.time >= start && l.time <= now && !own.contains { abs($0.time.timeIntervalSince(l.time)) < Self.interval }
        }
        if !extra.isEmpty {
            samples = (own + extra).sorted { $0.time < $1.time }
        }
        // On battery now: the charger came out just after the last time anything saw it in. The log goes back
        // further than the chart, so it can also tell a day and more on battery.
        if let last = samples.last, !last.onAC {
            let all = (samples + logged).sorted { $0.time < $1.time }
            if let i = all.lastIndex(where: { $0.onAC }), i + 1 < all.count { unpluggedAt = all[i + 1].time }
        }
        trim(now)
        save(force: true)
    }

    private func trim(_ now: Date) {
        let start = now.addingTimeInterval(-Self.keep)
        if let i = samples.firstIndex(where: { $0.time >= start }), i > 1 { samples.removeFirst(i - 1) }
    }

    private func save(force: Bool) {
        guard let file, force || Date().timeIntervalSince(lastSaved) > 60 else { return }
        lastSaved = Date()
        let saved = Saved(samples: samples, unpluggedAt: unpluggedAt)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: file, options: .atomic) }
    }

    // MARK: powerd's log

    private nonisolated static func readLog() async -> [Sample] {
        await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["-g", "log"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return parseLog(String(decoding: data, as: UTF8.self), since: Date().addingTimeInterval(-7 * 24 * 3600))
        }.value
    }

    /// Lines like `2026-11-23 09:37:41 -0700 Sleep ... Using Batt (Charge:41%) 95 secs` or
    /// `... Summary- [...] Using AC(Charge: 41)`.
    nonisolated static func parseLog(_ text: String, since: Date) -> [Sample] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var out: [Sample] = []
        for line in text.split(separator: "\n") where line.contains("Using ") && line.contains("Charge:") {
            guard line.count > 25, let time = formatter.date(from: String(line.prefix(25))), time >= since,
                  let using = line.range(of: "Using ") else { continue }
            let rest = line[using.upperBound...]
            let onAC: Bool
            if rest.hasPrefix("AC") { onAC = true } else if rest.hasPrefix("Batt") { onAC = false } else { continue }
            guard let c = rest.range(of: "Charge:") else { continue }
            let digits = rest[c.upperBound...].drop { $0 == " " }.prefix { $0.isNumber }
            guard let percent = Int(digits), (0...100).contains(percent) else { continue }
            out.append(Sample(time: time, percent: percent, onAC: onAC))
        }
        return out.sorted { $0.time < $1.time }
    }
}
