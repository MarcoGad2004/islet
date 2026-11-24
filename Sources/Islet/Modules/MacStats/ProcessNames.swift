import AppKit

/// One row of a "Using the most" list (DESIGN.md "App names in the lists"): an app with its helpers added up, or one
/// of macOS's own processes under a plain name with its real one underneath.
struct ProcessGroup: Identifiable, Equatable {
    var id: String
    var name: String
    /// The real process name(s), small under a macOS row; nil for an app.
    var detail: String?
    /// The app's bundle, for its icon; nil for macOS's own processes.
    var appPath: String?
    var value: Double
    /// Every process in the row, for the hover.
    var members: [String]
    /// Their process IDs, to quit them.
    var pids: [pid_t] = []
}

enum ProcessNames {
    /// macOS's own processes a person would meet here, by what they do. Only ones whose job is certain; any other keeps
    /// its own name.
    static let system: [String: String] = [
        "WindowServer": "Drawing the screen",
        "kernel_task": "macOS kernel",
        "launchd": "Starting system services",
        "corespotlightd": "Spotlight indexing",
        "mds": "Spotlight indexing",
        "mds_stores": "Spotlight indexing",
        "mdworker": "Spotlight indexing",
        "mdworker_shared": "Spotlight indexing",
        "mdsync": "Spotlight indexing",
        "spotlightknowledged": "Spotlight indexing",
        "spotlightknowledged.updater": "Spotlight indexing",
        "coreaudiod": "Sound",
        "screencapture": "Screenshot",
        "replayd": "Screen recording",
        "bluetoothd": "Bluetooth",
        "airportd": "Wi-Fi",
        "photoanalysisd": "Photos analysis",
        "mediaanalysisd": "Photos analysis",
        "photolibraryd": "Photos library",
        "backupd": "Time Machine",
        "softwareupdated": "Software Update",
        "cloudd": "iCloud",
        "bird": "iCloud Drive",
        "fileproviderd": "iCloud Drive",
        "nsurlsessiond": "Background downloads",
        "powerd": "Power management",
        "thermalmonitord": "Temperature monitoring",
        "syspolicyd": "App security checks",
        "XProtect": "Malware protection",
        "XProtectPluginService": "Malware protection",
        "trustd": "Certificate checks",
        "sharingd": "AirDrop and sharing",
        "locationd": "Location Services",
        "chronod": "Widgets",
        "WallpaperAgent": "Wallpaper",
        "logd": "System logging",
        "SimulatorTrampoline": "iOS Simulator",
        "Spotlight": "Spotlight",
    ]

    /// Groups processes into rows and keeps the `limit` biggest.
    @MainActor static func group(_ uses: [ProcessUse], limit: Int = 5) -> [ProcessGroup] {
        var rows: [String: ProcessGroup] = [:]
        for use in uses where use.value > 0 {
            let key: String, name: String, detail: String?, app: String?
            if let bundle = appBundle(use.path) {
                key = "app:" + bundle
                name = appName(bundle)
                detail = nil
                app = bundle
            } else if let plain = system[use.name] {
                key = "macos:" + plain
                name = plain
                detail = use.name
                app = nil
            } else {
                key = "process:" + (use.path.isEmpty ? use.name : use.path)
                name = use.name
                detail = nil
                app = nil
            }
            var row = rows[key] ?? ProcessGroup(id: key, name: name, detail: nil, appPath: app, value: 0, members: [])
            row.value += use.value
            row.pids.append(use.pid)
            if !row.members.contains(use.name) { row.members.append(use.name) }
            if detail != nil { row.detail = row.members.joined(separator: ", ") }
            rows[key] = row
        }
        return rows.values.sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }.prefix(limit).map { $0 }
    }

    /// The outermost `.app` the executable sits in, so a helper inside an app's Frameworks counts as that app.
    static func appBundle(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    /// The name the Finder shows ("Claude", not "Claude.app").
    @MainActor static func appName(_ bundle: String) -> String {
        if let cached = names[bundle] { return cached }
        let name = Bundle(path: bundle).flatMap {
            ($0.localizedInfoDictionary?["CFBundleDisplayName"] ?? $0.infoDictionary?["CFBundleDisplayName"]
                ?? $0.infoDictionary?["CFBundleName"]) as? String
        } ?? FileManager.default.displayName(atPath: bundle).replacingOccurrences(of: ".app", with: "")
        names[bundle] = name
        return name
    }

    @MainActor static func icon(_ bundle: String) -> NSImage {
        if let cached = icons[bundle] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: bundle)
        icons[bundle] = icon
        return icon
    }

    @MainActor private static var names: [String: String] = [:]
    @MainActor private static var icons: [String: NSImage] = [:]
}
