import AppKit

/// One row search can show (DESIGN.md "Search").
struct SearchItem: Identifiable, Equatable {
    enum Kind: Equatable { case app, shortcut, file, setting, calc, spotlight, web }
    /// "kind:identity". Also the key Islet remembers opened results by.
    let id: String
    var kind: Kind
    var name: String
    /// A file's folder (shown on the right), a Shortcut's identifier, the sum for an answer.
    var detail = ""
    var url: URL?
    /// Positions in `name` that matched, drawn brighter.
    var marks: [Int] = []
    var score = 0.0
    /// When it was last opened (the system's record for apps and files), for ranking and the recent row.
    var lastUsed: Date?

    /// The kind under a top hit.
    var kindLabel: String {
        switch kind {
        case .app: "Application"
        case .shortcut: "Shortcut"
        case .file: SearchIndex.shortPath(detail)
        case .setting: "System Settings"
        case .calc: "Calculator"
        case .spotlight, .web: ""
        }
    }
}

/// Matching and ranking (DESIGN.md "Search", "Matching"): a word's start beats the middle of a word, which beats the
/// letters in order (from three letters). Ties go to what was opened most recently.
enum SearchMatch {
    static func match(_ name: String, _ query: [String]) -> (score: Double, marks: [Int])? {
        guard !query.isEmpty else { return nil }
        let n = name.map { $0.lowercased() }
        let q = query
        func matches(at i: Int) -> Bool {
            guard i + q.count <= n.count else { return false }
            for j in 0..<q.count where n[i + j] != q[j] { return false }
            return true
        }
        func isWordStart(_ i: Int) -> Bool {
            i == 0 || !(n[i - 1].first?.isLetter ?? false || n[i - 1].first?.isNumber ?? false)
        }
        if matches(at: 0) { return (100 - Double(n.count - q.count) * 0.3, Array(0..<q.count)) }
        var firstInside: Int?
        if n.count > q.count {
            for i in 1...(n.count - q.count) where matches(at: i) {
                if isWordStart(i) { return (82 - Double(i) * 0.2, Array(i..<(i + q.count))) }
                if firstInside == nil { firstInside = i }
            }
        }
        if let i = firstInside { return (62 - Double(i) * 0.3, Array(i..<(i + q.count))) }
        let letters = q.filter { $0 != " " }
        guard letters.count >= 3 else { return nil }
        var pos = 0, last = -1, gaps = 0
        var marks: [Int] = []
        for ch in letters {
            guard let j = (pos..<n.count).first(where: { n[$0] == ch }) else { return nil }
            if last >= 0 { gaps += j - last - 1 }
            marks.append(j); last = j; pos = j + 1
        }
        let s = 42 - Double(gaps) * 1.6 - Double(marks[0]) * 0.6
        return s > 18 ? (s, marks) : nil
    }

    static func query(_ text: String) -> [String] { text.trimmingCharacters(in: .whitespaces).map { $0.lowercased() } }

    /// Up to 14 for something used today, fading over a couple of weeks.
    static func recency(_ d: Date?) -> Double {
        guard let d else { return 0 }
        let days = max(0, Date().timeIntervalSince(d) / 86_400)
        return 14 * exp(-days / 14)
    }
}

/// A sum typed into search ("12*7.5", "(3+4)/2", "15% * 80"): a small parser, never `eval` or `NSExpression`.
enum SearchCalculator {
    static func evaluate(_ raw: String) -> Double? {
        let src = Array(raw.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "x", with: "*").replacingOccurrences(of: ",", with: "")
            .filter { !$0.isWhitespace })
        let allowed = Set("0123456789.+-*/()^%")
        guard !src.isEmpty, src.allSatisfy({ allowed.contains($0) }), src.contains(where: \.isNumber) else { return nil }
        // At least one operator between two numbers, so "12" or "-4" alone isn't a sum.
        let ops = Set("+-*/^")
        guard src.indices.dropFirst().contains(where: { ops.contains(src[$0]) && (src[$0 - 1].isNumber || src[$0 - 1] == ")" || src[$0 - 1] == "%") })
        else { return nil }
        var i = 0
        func peek() -> Character? { i < src.count ? src[i] : nil }
        func number() throws -> Double {
            if peek() == "(" {
                i += 1; let v = try add()
                guard peek() == ")" else { throw CalcError.bad }
                i += 1; return try percent(v)
            }
            if peek() == "-" { i += 1; return -(try number()) }
            let start = i
            while let c = peek(), c.isNumber || c == "." { i += 1 }
            guard i > start, let v = Double(String(src[start..<i])) else { throw CalcError.bad }
            return try percent(v)
        }
        func percent(_ v: Double) throws -> Double {
            if peek() == "%" { i += 1; return v / 100 }
            return v
        }
        func power() throws -> Double {
            let b = try number()
            if peek() == "^" { i += 1; return pow(b, try power()) }
            return b
        }
        func mul() throws -> Double {
            var v = try power()
            while let c = peek(), c == "*" || c == "/" { i += 1; let r = try power(); v = c == "*" ? v * r : v / r }
            return v
        }
        func add() throws -> Double {
            var v = try mul()
            while let c = peek(), c == "+" || c == "-" { i += 1; let r = try mul(); v = c == "+" ? v + r : v - r }
            return v
        }
        guard let v = try? add(), i == src.count, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 8
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private enum CalcError: Error { case bad }
}

/// Where results come from (RESEARCH.md Q39-Q43): the app folders, the Spotlight index for files, the `shortcuts` tool,
/// and Islet's own list of System Settings pages.
@MainActor
final class SearchIndex {
    private(set) var apps: [SearchItem] = []
    private(set) var shortcuts: [SearchItem] = []
    private var appsLoaded: Date?
    private var shortcutsLoaded: Date?
    private var iconCache: [String: NSImage] = [:]

    // MARK: Apps

    /// Lists the app folders (1 ms) and reads when each was last opened. Cheap enough to do on every opening, at most
    /// once a minute.
    func refreshApps() {
        if let l = appsLoaded, Date().timeIntervalSince(l) < 60 { return }
        appsLoaded = Date()
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", home + "/Applications"]
        // Apps one folder down (a suite installed in its own folder).
        for d in ["/Applications", home + "/Applications"] {
            for sub in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where !sub.hasSuffix(".app") && !sub.hasPrefix(".") && sub != "Utilities" {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: d + "/" + sub, isDirectory: &isDir), isDir.boolValue { dirs.append(d + "/" + sub) }
            }
        }
        var seen = Set<String>()
        var found: [URL] = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        for d in dirs {
            for name in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where name.hasSuffix(".app") {
                found.append(URL(fileURLWithPath: d + "/" + name))
            }
        }
        let me = Bundle.main.bundleURL.standardizedFileURL
        apps = found.compactMap { url in
            guard url.standardizedFileURL != me else { return nil }
            var name = fm.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            guard seen.insert(name.lowercased()).inserted else { return nil }
            let used = MDItemCreateWithURL(nil, url as CFURL).flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
            return SearchItem(id: "app:" + url.path, kind: .app, name: name, url: url, lastUsed: used)
        }
    }

    /// The empty field's row: the 7 most recently opened apps.
    func recentApps(remembered: [String: Date]) -> [SearchItem] {
        apps.sorted { last($0, remembered) > last($1, remembered) }.prefix(7).map { $0 }
    }

    private func last(_ item: SearchItem, _ remembered: [String: Date]) -> Date {
        max(item.lastUsed ?? .distantPast, remembered[item.id] ?? .distantPast)
    }

    // MARK: Shortcuts

    /// `shortcuts list --show-identifiers` (about 60 ms), off the main thread, at most once a minute.
    func refreshShortcuts() {
        if let l = shortcutsLoaded, Date().timeIntervalSince(l) < 60 { return }
        shortcutsLoaded = Date()
        Task.detached(priority: .userInitiated) {
            let lines = Self.run("/usr/bin/shortcuts", ["list", "--show-identifiers"])
            let items: [SearchItem] = lines.split(separator: "\n").compactMap { line in
                // "Name (8C1D…-UUID)"
                guard line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) else { return nil }
                let name = String(line[..<open.lowerBound])
                let id = String(line[open.upperBound..<line.index(before: line.endIndex)])
                return SearchItem(id: "shortcut:" + id, kind: .shortcut, name: name, detail: id)
            }
            await MainActor.run { [weak self] in self?.shortcuts = items }
        }
    }

    nonisolated static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: System Settings pages

    struct SettingsPage { let name: String; let pane: String; let symbol: String; let color: UInt32 }

    /// System Settings pages by name. Several names can open the same page.
    static let settingsPages: [SettingsPage] = [
        .init(name: "Wi-Fi", pane: "com.apple.wifi-settings-extension", symbol: "wifi", color: 0x0A84FF),
        .init(name: "Bluetooth", pane: "com.apple.BluetoothSettings", symbol: "dot.radiowaves.left.and.right", color: 0x0A84FF),
        .init(name: "Network", pane: "com.apple.Network-Settings.extension", symbol: "network", color: 0x0A84FF),
        .init(name: "VPN", pane: "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", symbol: "network.badge.shield.half.filled", color: 0x0A84FF),
        .init(name: "Notifications", pane: "com.apple.Notifications-Settings.extension", symbol: "bell.badge.fill", color: 0xFF453A),
        .init(name: "Sound", pane: "com.apple.Sound-Settings.extension", symbol: "speaker.wave.2.fill", color: 0xFF375F),
        .init(name: "Focus", pane: "com.apple.Focus-Settings.extension", symbol: "moon.fill", color: 0x5E5CE6),
        .init(name: "Screen Time", pane: "com.apple.Screen-Time-Settings.extension", symbol: "hourglass", color: 0x5E5CE6),
        .init(name: "General", pane: "com.apple.systempreferences.GeneralSettings", symbol: "gearshape.fill", color: 0x8E8E93),
        .init(name: "Software Update", pane: "com.apple.Software-Update-Settings.extension", symbol: "arrow.triangle.2.circlepath", color: 0x8E8E93),
        .init(name: "Storage", pane: "com.apple.settings.Storage", symbol: "internaldrive.fill", color: 0x8E8E93),
        .init(name: "Date & Time", pane: "com.apple.Date-Time-Settings.extension", symbol: "clock.fill", color: 0x8E8E93),
        .init(name: "Sharing", pane: "com.apple.Sharing-Settings.extension", symbol: "person.2.fill", color: 0x8E8E93),
        .init(name: "Login Items", pane: "com.apple.LoginItems-Settings.extension", symbol: "list.bullet", color: 0x8E8E93),
        .init(name: "Time Machine", pane: "com.apple.Time-Machine-Settings.extension", symbol: "clock.arrow.circlepath", color: 0x30D158),
        .init(name: "Appearance", pane: "com.apple.Appearance-Settings.extension", symbol: "circle.lefthalf.filled", color: 0x1C1C1E),
        .init(name: "Accessibility", pane: "com.apple.Accessibility-Settings.extension", symbol: "accessibility", color: 0x0A84FF),
        .init(name: "Control Center", pane: "com.apple.ControlCenter-Settings.extension", symbol: "switch.2", color: 0x8E8E93),
        .init(name: "Desktop & Dock", pane: "com.apple.Desktop-Settings.extension", symbol: "dock.rectangle", color: 0x1C1C1E),
        .init(name: "Displays", pane: "com.apple.Displays-Settings.extension", symbol: "sun.max.fill", color: 0x0A84FF),
        .init(name: "Wallpaper", pane: "com.apple.Wallpaper-Settings.extension", symbol: "photo.fill", color: 0x64D2FF),
        .init(name: "Battery", pane: "com.apple.Battery-Settings.extension", symbol: "battery.100percent", color: 0x30D158),
        .init(name: "Lock Screen", pane: "com.apple.Lock-Screen-Settings.extension", symbol: "lock.fill", color: 0x1C1C1E),
        .init(name: "Touch ID & Password", pane: "com.apple.Touch-ID-Settings.extension", symbol: "touchid", color: 0xFF453A),
        .init(name: "Users & Groups", pane: "com.apple.Users-Groups-Settings.extension", symbol: "person.2.fill", color: 0x0A84FF),
        .init(name: "Passwords", pane: "com.apple.Passwords-Settings.extension", symbol: "key.fill", color: 0x8E8E93),
        .init(name: "Internet Accounts", pane: "com.apple.Internet-Accounts-Settings.extension", symbol: "at", color: 0x0A84FF),
        .init(name: "Privacy & Security", pane: "com.apple.settings.PrivacySecurity.extension", symbol: "hand.raised.fill", color: 0x0A84FF),
        .init(name: "Keyboard", pane: "com.apple.Keyboard-Settings.extension", symbol: "keyboard.fill", color: 0x8E8E93),
        .init(name: "Keyboard Shortcuts", pane: "com.apple.Keyboard-Settings.extension", symbol: "command", color: 0x8E8E93),
        .init(name: "Trackpad", pane: "com.apple.Trackpad-Settings.extension", symbol: "rectangle.and.hand.point.up.left.fill", color: 0x8E8E93),
        .init(name: "Mouse", pane: "com.apple.Mouse-Settings.extension", symbol: "computermouse.fill", color: 0x8E8E93),
        .init(name: "Printers & Scanners", pane: "com.apple.Print-Scan-Settings.extension", symbol: "printer.fill", color: 0x8E8E93),
        .init(name: "Spotlight", pane: "com.apple.Spotlight-Settings.extension", symbol: "magnifyingglass", color: 0x8E8E93),
    ]

    static func settingsItems() -> [SearchItem] {
        settingsPages.map { p in
            SearchItem(id: "setting:" + p.name, kind: .setting, name: p.name, url: URL(string: "x-apple.systempreferences:" + p.pane))
        }
    }

    static func page(named name: String) -> SettingsPage? { settingsPages.first { $0.name == name } }

    // MARK: Icons

    func icon(for item: SearchItem) -> NSImage? {
        guard let url = item.url, item.kind == .app || item.kind == .file else { return nil }
        if let i = iconCache[url.path] { return i }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        if iconCache.count > 400 { iconCache.removeAll() }
        iconCache[url.path] = i
        return i
    }

    static let calculatorURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")

    /// "~/Documents/GitHub/islet/docs", cut in the middle when long.
    nonisolated static func shortPath(_ folder: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var p = folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
        if p.count > 34 { p = String(p.prefix(13)) + "…" + String(p.suffix(20)) }
        return p
    }
}

/// Files from the Spotlight index (RESEARCH.md Q40, Q41): one query per change of the text, the previous one stopped.
/// Two letters or more; `~/Library`, hidden folders and the insides of bundles are left out.
@MainActor
final class SearchFiles {
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    /// Called with the files found for `text` (already filtered), newest first.
    var onResults: ((String, [SearchItem]) -> Void)?

    func search(_ text: String) {
        stop()
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { onResults?(t, []); return }
        let q = NSMetadataQuery()
        let escaped = t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "?", with: "\\?")
        q.predicate = NSPredicate(format: "kMDItemFSName LIKE[cd] %@ AND kMDItemContentType != 'com.apple.application-bundle'", "*\(escaped)*")
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        generation += 1
        let gen = generation
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished(gen, t) }
        }
        query = q
        q.start()
    }

    private var generation = 0

    private func finished(_ gen: Int, _ text: String) {
        guard gen == generation, let q = query else { return }
        q.disableUpdates()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let library = home + "/Library/"
        var items: [SearchItem] = []
        for i in 0..<min(q.resultCount, 600) {
            guard let m = q.result(at: i) as? NSMetadataItem, let path = m.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if path.hasPrefix(library) || path.contains("/.") || Self.skipped.contains(where: path.contains) { continue }
            let url = URL(fileURLWithPath: path)
            let used = m.value(forAttribute: "kMDItemLastUsedDate") as? Date
            var item = SearchItem(id: "file:" + path, kind: .file, name: url.lastPathComponent,
                                  detail: url.deletingLastPathComponent().path, url: url, lastUsed: used)
            // Deep in a folder tree (a project's sources) counts for less than near the top of home.
            let depth = path.dropFirst(home.count).filter { $0 == "/" }.count
            item.score = -Double(max(0, depth - 3)) * 1.5
            items.append(item)
            if items.count >= 200 { break }
        }
        stop()
        onResults?(text, items)
    }

    /// Inside bundles, and the build and dependency folders of code projects: never what someone searches for.
    private static let skipped = [".app/", ".bundle/", ".framework/", ".photoslibrary/", ".xcodeproj/", ".xcworkspace/",
                                  "/node_modules/", "/Pods/", "/DerivedData/", "/site-packages/", "/__pycache__/",
                                  "/venv/", "/vendor/", "/dist/", "/build/", "/target/", "/.build/"]

    func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
