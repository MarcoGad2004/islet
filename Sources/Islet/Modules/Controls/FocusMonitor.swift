import AppKit
import SwiftUI

struct FocusMode: Equatable {
    var id: String
    var name: String
    var symbol: String
    /// The colour chosen for this Focus in System Settings, e.g. "systemOrangeColor"; nil when none is set.
    var tintName: String?

    /// The Focus's own colour, as macOS shows it; Do Not Disturb's indigo-purple when it has none.
    var color: Color {
        // The name comes from a private file: only a system colour accessor NSColor really has is performed (an
        // unknown selector would raise an exception that can't be caught).
        if let tintName, tintName.hasPrefix("system"), tintName.hasSuffix("Color") {
            let sel = NSSelectorFromString(tintName)
            if (NSColor.self as AnyObject).responds(to: sel), let c = NSColor.perform(sel)?.takeUnretainedValue() as? NSColor {
                return Color(nsColor: c)
            }
        }
        return Color(hex: 0xBF5AF2)
    }
}

/// The active Focus, read from the Do Not Disturb database (needs Full Disk Access). Read-only: macOS has no public
/// way to set a Focus. The folder is watched, and one change writes it several times, so reads are debounced.
@MainActor @Observable
final class FocusMonitor {
    private(set) var active: FocusMode?
    private(set) var accessGranted = false

    /// (previous, new) when the active Focus changed.
    @ObservationIgnored var onChange: ((FocusMode?, FocusMode?) -> Void)?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var debounce: Task<Void, Never>?

    private static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")

    @ObservationIgnored private var clock: Timer?

    func start() {
        let result = Self.read()
        accessGranted = result.granted
        active = result.mode
        watch()
        // A Focus turned on by its schedule doesn't write the folder when the time comes, so look once a minute too.
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.changed() } }
        RunLoop.main.add(t, forMode: .common)
        clock = t
    }

    /// Call after the user may have granted Full Disk Access.
    func retry() {
        let result = Self.read()
        accessGranted = result.granted
        if result.granted, source == nil { active = result.mode; watch() }
    }

    private func watch() {
        guard source == nil else { return }
        let fd = open(Self.dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func changed() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            let now = Self.read().mode
            guard now != self.active else { return }
            let old = self.active
            self.active = now
            self.onChange?(old, now)
        }
    }

    // MARK: Reading

    private static func read() -> (granted: Bool, mode: FocusMode?) {
        guard let assertions = try? Data(contentsOf: dir.appendingPathComponent("Assertions.json")) else { return (false, nil) }
        let configs = modeConfigurations()

        // Turned on by hand, from Control Center or another device: an assertion record. The newest one wins.
        var id: String?
        if let json = try? JSONSerialization.jsonObject(with: assertions) as? [String: Any],
           let records = (json["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]] {
            let newest = records.max { ($0["assertionStartDateTimestamp"] as? Double ?? 0) < ($1["assertionStartDateTimestamp"] as? Double ?? 0) }
            id = (newest?["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
        }
        // Turned on by its schedule: no record, only the schedule in the mode's configuration.
        if id == nil { id = configs.first { scheduledNow($0.value) }?.key }
        guard let id else { return (true, nil) }

        var name = id.split(separator: ".").last.map(String.init)?.capitalized ?? "Focus"
        var symbol = "moon.fill"
        var tint: String?
        if let mode = configs[id]?["mode"] as? [String: Any] {
            if let n = mode["name"] as? String { name = n }
            if let s = mode["symbolImageName"] as? String, NSImage(systemSymbolName: s, accessibilityDescription: nil) != nil { symbol = s }
            tint = mode["tintColorName"] as? String
        }
        return (true, FocusMode(id: id, name: name, symbol: symbol, tintName: tint))
    }

    private static func modeConfigurations() -> [String: [String: Any]] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("ModeConfigurations.json")),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cfgs = (j["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any] else { return [:] }
        return cfgs.compactMapValues { $0 as? [String: Any] }
    }

    /// Whether one of the mode's enabled time schedules covers now. `timePeriodWeekdays` is a bit per day from
    /// Sunday (bit 0); missing or 0 means every day. A schedule past midnight counts from the day it started.
    private static func scheduledNow(_ config: [String: Any], at date: Date = Date()) -> Bool {
        guard let triggers = (config["triggers"] as? [String: Any])?["triggers"] as? [[String: Any]] else { return false }
        let cal = Calendar.current
        let now = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let today = cal.component(.weekday, from: date) - 1 // 0 = Sunday
        func int(_ t: [String: Any], _ k: String) -> Int { (t[k] as? NSNumber)?.intValue ?? 0 }
        for t in triggers where (t["class"] as? String) == "DNDModeConfigurationScheduleTrigger" && int(t, "enabledSetting") == 2 {
            let start = int(t, "timePeriodStartTimeHour") * 60 + int(t, "timePeriodStartTimeMinute")
            let end = int(t, "timePeriodEndTimeHour") * 60 + int(t, "timePeriodEndTimeMinute")
            let days = int(t, "timePeriodWeekdays")
            func on(_ day: Int) -> Bool { days == 0 || days & (1 << ((day + 7) % 7)) != 0 }
            if start < end, now >= start, now < end, on(today) { return true }
            if start > end, (now >= start && on(today)) || (now < end && on(today - 1)) { return true }
        }
        return false
    }
}
