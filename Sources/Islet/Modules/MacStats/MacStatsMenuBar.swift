import AppKit
import SwiftUI

// Mac Stats' menu bar item (DESIGN.md "Mac Stats (1.7)", Menu bar): the temperature and power stacked, the fan speed,
// then the meters, in one status item left of Islet's own.

/// Settings > Mac Stats, as UserDefaults keys.
enum MacStatsSettings {
    static let enabled = "macStatsEnabled"
    static let meters = "macStatsMeters"
    static let efficiency = "macStatsMeterEfficiency"
    static let performance = "macStatsMeterPerformance"
    static let gpu = "macStatsMeterGPU"
    static let memory = "macStatsMeterMemory"
    static let readouts = "macStatsReadouts"
    static let temperature = "macStatsTemperature"
    static let power = "macStatsPower"
    static let fan = "macStatsFan"
    static let temperatureSource = "macStatsTemperatureSource"
    static let colourParts = "macStatsColourParts"
    static let warnings = "macStatsWarnings"
    /// Which stats may warn (each on by default, once `warnings` is on): the switches under "Warn in yellow and red".
    enum WarnPart: CaseIterable {
        case efficiency, performance, gpu, memory, temperature
        var key: String {
            switch self {
            case .efficiency: "macStatsWarnEfficiency"
            case .performance: "macStatsWarnPerformance"
            case .gpu: "macStatsWarnGPU"
            case .memory: "macStatsWarnMemory"
            case .temperature: "macStatsWarnTemperature"
            }
        }
    }
    /// Whether this stat shows yellow and red: warnings on, and this one's switch on.
    static func warns(_ part: WarnPart) -> Bool { on(warnings) && on(part.key) }
    /// `level`, or `.normal` where this stat doesn't warn.
    static func gated(_ level: StatLevel, _ part: WarnPart) -> StatLevel { warns(part) ? level : .normal }
    /// Seconds between readings: 1, 2 or 5.
    static let interval = "macStatsInterval"

    /// Every switch is on by default except the feature itself.
    static func on(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? (key != enabled) }

    static var isEnabled: Bool { on(enabled) }
    /// Every Mac Stats setting as it is now, to tell when one changed.
    static var signature: String {
        let d = UserDefaults.standard
        let keys = [enabled, meters, efficiency, performance, gpu, memory, readouts, temperature, power, fan, colourParts, warnings] + WarnPart.allCases.map(\.key)
        return keys.map { on($0) ? "1" : "0" }.joined() + MacStatsMenuBarContent.Part.allCases.map { "\(MacStatsPalette.index($0))" }.joined(separator: ",")
            + "\(d.string(forKey: temperatureSource) ?? "")\(intervalSeconds)"
    }
    static var intervalSeconds: Int { [1, 2, 5].contains(UserDefaults.standard.integer(forKey: interval)) ? UserDefaults.standard.integer(forKey: interval) : 2 }
}

/// The colours a part can take (1.7.1, owner 2026-11-24): sixteen across the rainbow, each a bright one for a dark
/// menu bar and a deeper one for a light one. Each part's own colour is one of them, so nothing changes until a
/// different one is picked. Red and yellow are in it too, though the warnings use them.
enum MacStatsPalette {
    struct Swatch { let name: String; let dark: UInt32; let light: UInt32 }
    static let all: [Swatch] = [
        Swatch(name: "Red", dark: 0xFF453A, light: 0xD70015),
        Swatch(name: "Vermilion", dark: 0xFF6A3D, light: 0xC23B10),
        Swatch(name: "Orange", dark: 0xFF9F0A, light: 0xC93400),
        Swatch(name: "Amber", dark: 0xFFC20A, light: 0xA36A00),
        Swatch(name: "Yellow", dark: 0xFFE14D, light: 0x9A7B00),
        Swatch(name: "Lime", dark: 0xB6E34A, light: 0x5F8A00),
        Swatch(name: "Green", dark: 0x32D74B, light: 0x248A3D),
        Swatch(name: "Emerald", dark: 0x3DDC97, light: 0x0C8A5A),
        Swatch(name: "Teal", dark: 0x40D0C8, light: 0x007C80),
        Swatch(name: "Cyan", dark: 0x64D2FF, light: 0x0071A4),
        Swatch(name: "Sky", dark: 0x5AB4FF, light: 0x0A64C8),
        Swatch(name: "Blue", dark: 0x0A84FF, light: 0x0040DD),
        Swatch(name: "Indigo", dark: 0x5E5CE6, light: 0x3634A3),
        Swatch(name: "Purple", dark: 0xBF5AF2, light: 0x8944AB),
        Swatch(name: "Magenta", dark: 0xE85AD8, light: 0xA8189B),
        Swatch(name: "Pink", dark: 0xFF5E8A, light: 0xC20F4B),
    ]

    static func key(_ part: MacStatsMenuBarContent.Part) -> String {
        switch part {
        case .efficiency: "macStatsColourEfficiency"
        case .performance: "macStatsColourPerformance"
        case .gpu: "macStatsColourGPU"
        case .memory: "macStatsColourMemory"
        }
    }

    /// Where each part starts: its colour before there was a choice.
    static func defaultIndex(_ part: MacStatsMenuBarContent.Part) -> Int {
        switch part {
        case .efficiency: 6
        case .performance: 11
        case .gpu: 13
        case .memory: 9
        }
    }

    static func index(_ part: MacStatsMenuBarContent.Part) -> Int {
        guard let i = UserDefaults.standard.object(forKey: key(part)) as? Int, all.indices.contains(i) else { return defaultIndex(part) }
        return i
    }
}

enum TemperatureSource: String, CaseIterable {
    case cpuAverage, cpuHottest, gpu
    static var current: TemperatureSource {
        UserDefaults.standard.string(forKey: MacStatsSettings.temperatureSource).flatMap(Self.init) ?? .cpuAverage
    }
}

/// What the item shows, worked out from a reading and the settings: kept apart from the drawing so it can be tested.
struct MacStatsMenuBarContent: Equatable {
    enum Part: CaseIterable {
        case efficiency, performance, gpu, memory
        var warnPart: MacStatsSettings.WarnPart {
            switch self {
            case .efficiency: .efficiency
            case .performance: .performance
            case .gpu: .gpu
            case .memory: .memory
            }
        }
    }
    struct Bar: Equatable { var part: Part; var value: Double; var level: StatLevel }
    struct Readout: Equatable {
        var text: String
        var level: StatLevel
        /// Under the number: "rpm", "manual" while fan control holds the fans, or "fans" under "Off".
        var unit: String? = nil
    }

    var temperature: Readout?
    var power: Readout?
    var fan: Readout?
    var fansHeld = false
    var bars: [Bar] = []

    var isEmpty: Bool { temperature == nil && power == nil && fan == nil && bars.isEmpty }

    /// `levels` are the held warning levels (`LevelHold`); without warnings everything is `.normal`.
    static func make(_ s: MacStatsSnapshot, levels: [Part: StatLevel], temperatureLevel: StatLevel,
                     fahrenheit: Bool, on: (String) -> Bool = MacStatsSettings.on,
                     source: TemperatureSource = .current) -> MacStatsMenuBarContent {
        var c = MacStatsMenuBarContent()
        if on(MacStatsSettings.readouts) {
            if on(MacStatsSettings.temperature), let celsius = celsius(s, source) {
                let shown = fahrenheit ? celsius * 9 / 5 + 32 : celsius
                c.temperature = Readout(text: "\(Int(shown.rounded()))°", level: temperatureLevel)
            }
            if on(MacStatsSettings.power), let w = s.systemWatts {
                c.power = Readout(text: "\(Int(w.rounded())) W", level: .normal)
            }
            if on(MacStatsSettings.fan), let fan = s.fastestFan {
                c.fan = fan.rpm < 1 ? Readout(text: "Off", level: .normal, unit: "fans")
                    : Readout(text: rpm(fan.rpm), level: .normal, unit: s.fansHeld ? "manual" : "rpm")
                c.fansHeld = s.fansHeld
            }
        }
        if on(MacStatsSettings.meters) {
            let parts: [(Part, String, Double?)] = [
                (.efficiency, MacStatsSettings.efficiency, s.cpu?.efficiencyCount == 0 ? nil : s.cpu?.efficiency),
                (.performance, MacStatsSettings.performance, s.cpu?.performance),
                (.gpu, MacStatsSettings.gpu, s.gpu?.utilization),
                (.memory, MacStatsSettings.memory, s.memory?.fraction),
            ]
            c.bars = parts.compactMap { part, key, value in
                guard on(key), let value else { return nil }
                return Bar(part: part, value: value, level: levels[part] ?? .normal)
            }
        }
        return c
    }

    /// "5.3k" from 1,000 rpm, so it fits over "rpm"; "800" below.
    static func rpm(_ rpm: Double) -> String {
        rpm >= 1000 ? String(format: "%.1fk", rpm / 1000) : "\(Int((rpm / 10).rounded()) * 10)"
    }

    static func celsius(_ s: MacStatsSnapshot, _ source: TemperatureSource) -> Double? {
        switch source {
        case .cpuAverage: s.thermal.cpuAverage
        case .cpuHottest: s.thermal.cpuHottest
        case .gpu: s.thermal.gpuAverage
        }
    }

    /// What a reading's raw warning level is, before the 5 s hold.
    static func rawLevel(_ part: Part, _ s: MacStatsSnapshot) -> StatLevel {
        switch part {
        case .efficiency: StatLevel(load: s.cpu?.efficiency ?? 0)
        case .performance: StatLevel(load: s.cpu?.performance ?? 0)
        case .gpu: StatLevel(load: s.gpu?.utilization ?? 0)
        case .memory: StatLevel(s.memory?.pressure ?? .normal)
        }
    }

    /// For VoiceOver and the tooltip.
    var spoken: String {
        let names: [Part: String] = [.efficiency: "Efficiency cores", .performance: "Performance cores", .gpu: "GPU", .memory: "Memory"]
        var parts = bars.map { "\(names[$0.part]!) \(Int(($0.value * 100).rounded()))%" }
        if let t = temperature { parts.append("Temperature \(t.text)") }
        if let p = power { parts.append("Power \(p.text)") }
        if let f = fan { parts.append(f.text == "Off" ? "Fans off" : "Fans \(f.text) rpm" + (fansHeld ? ", set by you" : "")) }
        return parts.joined(separator: ", ")
    }
}

/// The item's look (DESIGN.md "Mac Stats (1.7)", Menu bar): two stacked columns of numbers, then the meters.
enum MacStatsMenuBar {
    static let height: CGFloat = 22
    /// The GPU and memory bars; the CPU bar is twice as wide, its halves the efficiency and performance cores.
    static let barWidth: CGFloat = 8
    static let barHeight: CGFloat = 20
    static let barGap: CGFloat = 2.5
    static let columnGap: CGFloat = 5
    static let sectionGap: CGFloat = 6
    static let pad: CGFloat = 2

    /// A part's colour: the one chosen in Settings > Mac Stats, else its own (`MacStatsPalette`).
    static func colour(_ part: MacStatsMenuBarContent.Part) -> NSColor {
        let swatch = MacStatsPalette.all[MacStatsPalette.index(part)]
        return dynamic(swatch.dark, swatch.light)
    }

    static let warning = dynamic(0xFFD60A, 0xB25000)
    static let critical = dynamic(0xFF453A, 0xD70015)

    static func colour(_ level: StatLevel) -> NSColor? {
        switch level {
        case .normal: nil
        case .warning: warning
        case .critical: critical
        }
    }

    fileprivate static func dynamic(_ dark: UInt32, _ light: UInt32) -> NSColor {
        NSColor(name: nil) { a in
            let hex = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }

    static var valueFont: NSFont { .monospacedDigitSystemFont(ofSize: 10, weight: .semibold) }
    static var unitFont: NSFont { .systemFont(ofSize: 10, weight: .medium) }

    private struct Line {
        var text: String
        var font: NSFont
        var level: StatLevel = .normal
        var dim = false
        var width: CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
    }

    /// One image for the whole item: temperature over power, the fan speed over "rpm" ("manual" while held), then the bars. Colours resolve
    /// when it's drawn, in the menu bar's own appearance.
    static func image(_ c: MacStatsMenuBarContent, colourParts: Bool) -> NSImage {
        // Each column with the widest text it usually holds, so the item keeps its width as the numbers change: a
        // change of width moves every menu bar icon to its left.
        var columns: [(lines: [Line], room: [Line])] = []
        let pair = [c.temperature.map { Line(text: $0.text, font: valueFont, level: $0.level) },
                    c.power.map { Line(text: $0.text, font: valueFont, level: $0.level) }].compactMap { $0 }
        if !pair.isEmpty {
            columns.append((pair, [Line(text: c.temperature != nil ? "188°" : "", font: valueFont),
                                   Line(text: c.power != nil ? "88 W" : "", font: valueFont)]))
        }
        if let f = c.fan {
            columns.append(([Line(text: f.text, font: valueFont), Line(text: f.unit ?? "", font: unitFont, dim: true)],
                            [Line(text: "8.8k", font: valueFont), Line(text: "rpm", font: unitFont)]))
        }

        // Left to right.
        var x = pad
        var placed: [(lines: [Line], x: CGFloat, width: CGFloat)] = []
        for (i, column) in columns.enumerated() {
            let lines = column.lines
            if i > 0 { x += columnGap }
            let w = (lines + column.room).map(\.width).max() ?? 0
            placed.append((lines, x, w))
            x += w
        }
        // The CPU's two halves make one bar; one alone (the other turned off) is a plain bar.
        let cpu = c.bars.filter { $0.part == .efficiency || $0.part == .performance }
        let rest = c.bars.filter { $0.part == .gpu || $0.part == .memory }
        var bars: [(parts: [MacStatsMenuBarContent.Bar], x: CGFloat)] = []
        var bx = columns.isEmpty ? x : x + sectionGap
        for group in ([cpu] + rest.map { [$0] }) where !group.isEmpty {
            if !bars.isEmpty { bx += barGap }
            bars.append((group, bx))
            bx += barWidth * CGFloat(group.count)
        }
        let total = (bars.isEmpty ? x : bx) + pad

        let image = NSImage(size: NSSize(width: max(total, 1), height: height), flipped: false) { _ in
            let ink = NSColor.labelColor
            let mid = height / 2
            for col in placed {
                for (row, line) in col.lines.enumerated() {
                    let colour = colour(line.level) ?? (line.dim ? ink.withAlphaComponent(0.55) : ink)
                    let text = NSAttributedString(string: line.text, attributes: [.font: line.font, .foregroundColor: colour])
                    let size = text.size()
                    // Right-aligned; one line sits in the middle, two share the height.
                    let y = col.lines.count == 1 ? mid - size.height / 2 : row == 0 ? mid - 0.5 : mid - size.height + 0.5
                    text.draw(at: NSPoint(x: col.x + col.width - ceil(size.width), y: y))
                }
            }
            for bar in bars {
                let rect = NSRect(x: bar.x, y: mid - barHeight / 2, width: barWidth * CGFloat(bar.parts.count), height: barHeight)
                let shape = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
                ink.withAlphaComponent(0.3).setFill()
                shape.fill()
                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                for (i, part) in bar.parts.enumerated() {
                    (colour(part.level) ?? (colourParts ? colour(part.part) : ink)).setFill()
                    // At least a sliver shows above 0, as on the battery.
                    let fill = part.value <= 0.005 ? 0 : max(1, barHeight * min(part.value, 1))
                    NSRect(x: rect.minX + barWidth * CGFloat(i), y: rect.minY, width: barWidth, height: fill).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = c.spoken
        return image
    }
}

/// The status item itself: shown while Mac Stats is on and has something to show, redrawn on every reading.
@MainActor
final class MacStatsStatusItem {
    /// Right-click or Control/Option-click: the app's menu. A plain click opens the stats panel.
    var onMenu: ((NSStatusItem) -> Void)?

    private var item: NSStatusItem?
    private var holds: [MacStatsMenuBarContent.Part: LevelHold] = [:]
    private var temperatureHold = LevelHold()
    private var defaultsObserver: NSObjectProtocol?
    private let panelState = MacStatsPanelState()
    private lazy var panel: MenuBarPanel = {
        let panel = MenuBarPanel { [panelState] _ in AnyView(MacStatsView(stats: .shared, state: panelState)) }
        // Each opening starts on the overview.
        panel.willShow = { [weak self] in
            self?.panelState.page = .overview
            MacStats.shared.prefetchProcesses()
        }
        panel.didClose = { MacStats.shared.wantsProcesses = false }
        return panel
    }()

    /// Where the item starts, in points from the menu bar's right edge: left of Islet's own (`AppDelegate.startPosition`).
    private static let startPosition = 300
    private static let name = "IsletMacStats"

    init() {
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        apply()
    }

    private var applying = false
    private var appliedSettings: String?

    /// Shows or hides the item and starts or stops the readings to match Settings.
    func apply() {
        // Creating the item writes its position to UserDefaults, which calls this again.
        guard !applying else { return }
        // Islet writes other defaults all the time; only a change to Mac Stats' own does anything.
        let settings = MacStatsSettings.signature
        guard settings != appliedSettings else { return }
        appliedSettings = settings
        applying = true
        defer { applying = false }
        let wanted = MacStatsSettings.isEnabled
            && ((MacStatsSettings.on(MacStatsSettings.meters)
                 && [MacStatsSettings.efficiency, MacStatsSettings.performance, MacStatsSettings.gpu, MacStatsSettings.memory].contains(where: MacStatsSettings.on))
                || (MacStatsSettings.on(MacStatsSettings.readouts)
                    && [MacStatsSettings.temperature, MacStatsSettings.power, MacStatsSettings.fan].contains(where: MacStatsSettings.on)))
        let stats = MacStats.shared
        stats.interval = .seconds(MacStatsSettings.intervalSeconds)
        if wanted {
            if item == nil {
                build()
                // Draw the pages once off screen while nothing's open, so the first one opened doesn't stall loading
                // Charts and fonts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MacStatsView.warmUp() }
            }
            if !stats.running {
                stats.start()
                watch()
            }
            redraw()
        } else {
            if let item {
                panel.close()
                NSStatusBar.system.removeStatusItem(item)
            }
            item = nil
            lastImage = nil
            if MacStatsSettings.isEnabled == false { stats.stop() }
            // With no item (and no panel) there is nowhere to see or change the fans: give them back to macOS, rather
            // than leaving them held, with the heartbeat keeping the helper from doing it, until the app quits.
            if FanControl.shared.mode != .automatic { FanControl.shared.setAutomatic() }
        }
    }

    private func build() {
        let position = "NSStatusItem Preferred Position \(Self.name)"
        if UserDefaults.standard.object(forKey: position) == nil { UserDefaults.standard.set(Self.startPosition, forKey: position) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.name
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.item = item
    }

    /// Whether an observation is registered: one at a time, however often Mac Stats is switched off and on (each
    /// leftover one would redraw the item again on every reading).
    private var watching = false

    /// Observation fires once per registration, so each change registers again.
    private func watch() {
        guard !watching else { return }
        watching = true
        withObservationTracking { _ = MacStats.shared.snapshot } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.watching = false
                guard MacStats.shared.running else { return }
                self.redraw()
                self.watch()
            }
        }
    }

    private func redraw() {
        guard let button = item?.button else { return }
        let s = MacStats.shared.snapshot
        var levels: [MacStatsMenuBarContent.Part: StatLevel] = [:]
        for part in MacStatsMenuBarContent.Part.allCases {
            var hold = holds[part] ?? LevelHold()
            levels[part] = MacStatsSettings.warns(part.warnPart) ? hold.update(MacStatsMenuBarContent.rawLevel(part, s), at: s.date) : .normal
            holds[part] = hold
        }
        let celsius = MacStatsMenuBarContent.celsius(s, .current)
        let tempLevel = MacStatsSettings.warns(.temperature) ? temperatureHold.update(celsius.map { StatLevel(celsius: $0) } ?? .normal, at: s.date) : .normal
        let content = MacStatsMenuBarContent.make(s, levels: levels, temperatureLevel: tempLevel,
                                                  fahrenheit: Locale.current.measurementSystem == .us)
        // Most readings at rest give the same picture: building it (measuring the text, drawing) is the cost.
        let colourParts = MacStatsSettings.on(MacStatsSettings.colourParts)
        let signature = MacStatsSettings.signature
        let image = LastImage(content: content, colourParts: colourParts, settings: signature)
        guard image != lastImage || button.image == nil else { return }
        lastImage = image
        button.image = MacStatsMenuBar.image(content, colourParts: colourParts)
        button.toolTip = content.spoken
        button.setAccessibilityLabel(content.spoken)
    }

    /// What the item's picture was built from, to skip building it again when nothing changed.
    private struct LastImage: Equatable {
        var content: MacStatsMenuBarContent
        var colourParts: Bool
        var settings: String
    }
    private var lastImage: LastImage?

    @objc private func clicked() {
        guard let item, let button = item.button else { return }
        let e = NSApp.currentEvent
        let wantsMenu = e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true || e?.modifierFlags.contains(.option) == true
        if wantsMenu {
            panel.close()
            onMenu?(item)
        } else {
            panel.toggle(under: button)
        }
    }
}
