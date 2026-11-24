import AppKit
import SwiftUI
import QuartzCore

// Mac Stats' menu bar item (DESIGN.md "Mac Stats (1.7)", Menu bar): the temperature, power and fan readouts, then the
// four meters, in one status item left of Islet's own.

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
    /// Seconds between readings: 1, 2 or 5.
    static let interval = "macStatsInterval"

    /// Every switch is on by default except the feature itself.
    static func on(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? (key != enabled) }

    static var isEnabled: Bool { on(enabled) }
    static var intervalSeconds: Int { [1, 2, 5].contains(UserDefaults.standard.integer(forKey: interval)) ? UserDefaults.standard.integer(forKey: interval) : 2 }
}

enum TemperatureSource: String, CaseIterable {
    case cpuAverage, cpuHottest, gpu
    static var current: TemperatureSource {
        UserDefaults.standard.string(forKey: MacStatsSettings.temperatureSource).flatMap(Self.init) ?? .cpuAverage
    }
}

/// What the item shows, worked out from a reading and the settings: kept apart from the drawing so it can be tested.
struct MacStatsMenuBarContent: Equatable {
    enum Part: CaseIterable { case efficiency, performance, gpu, memory }
    struct Bar: Equatable { var part: Part; var value: Double; var level: StatLevel }
    struct Readout: Equatable { var text: String; var level: StatLevel }

    var temperature: Readout?
    var power: Readout?
    var fan: Readout?
    /// The faster fan's share of full speed, for how fast the glyph turns.
    var fanFraction: Double = 0
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
                c.fan = Readout(text: fan.rpm < 1 ? "Off" : "\(Int((fan.fraction * 100).rounded()))%", level: .normal)
                c.fanFraction = fan.fraction
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
        if let f = fan { parts.append("Fans \(f.text)" + (fansHeld ? ", set by you" : "")) }
        return parts.joined(separator: ", ")
    }
}

/// The item's look: sizes in points and the colours (DESIGN.md "Mac Stats (1.7)", Colours).
enum MacStatsMenuBar {
    static let height: CGFloat = 22
    static let barWidth: CGFloat = 5
    static let barHeight: CGFloat = 15
    static let cpuGap: CGFloat = 1.5
    static let groupGap: CGFloat = 2.5
    static let readoutGap: CGFloat = 5
    static let glyphGap: CGFloat = 1
    static let sectionGap: CGFloat = 7
    static let glyphSize: CGFloat = 13
    static let pad: CGFloat = 2

    static func colour(_ part: MacStatsMenuBarContent.Part) -> NSColor {
        switch part {
        case .efficiency: dynamic(0x32D74B, 0x248A3D)
        case .performance: dynamic(0x0A84FF, 0x0040DD)
        case .gpu: dynamic(0xBF5AF2, 0x8944AB)
        case .memory: dynamic(0x64D2FF, 0x0071A4)
        }
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

    private static func dynamic(_ dark: UInt32, _ light: UInt32) -> NSColor {
        NSColor(name: nil) { a in
            let hex = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }

    static var font: NSFont { NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular) }

    /// The image, and where in it the fan glyph goes (drawn by `FanSpinView` on top, so it can turn without redrawing).
    /// Colours resolve when the image is drawn, in the menu bar's own appearance.
    static func image(_ c: MacStatsMenuBarContent, colourParts: Bool) -> (NSImage, fan: NSRect?) {
        let font = font
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ s: String) -> CGFloat { ceil((s as NSString).size(withAttributes: attrs).width) }

        // Lay out left to right.
        var items: [(kind: String, x: CGFloat, w: CGFloat)] = []
        var x = pad
        for (kind, readout) in [("temp", c.temperature), ("power", c.power), ("fan", c.fan)] {
            guard let readout else { continue }
            if !items.isEmpty { x += readoutGap }
            let w = glyphSize + glyphGap + width(readout.text) + (kind == "fan" && c.fansHeld ? 6 : 0)
            items.append((kind, x, w))
            x += w
        }
        let barsX = items.isEmpty ? x : x + sectionGap
        var barXs: [CGFloat] = []
        var bx = barsX
        for (i, bar) in c.bars.enumerated() {
            if i > 0 { bx += (bar.part == .performance && c.bars[i - 1].part == .efficiency) ? cpuGap : groupGap }
            barXs.append(bx)
            bx += barWidth
        }
        let total = (c.bars.isEmpty ? x : bx) + pad
        var fanRect: NSRect?

        let image = NSImage(size: NSSize(width: max(total, 1), height: height), flipped: false) { _ in
            let ink = NSColor.labelColor
            let midY = height / 2
            for item in items {
                let readout = item.kind == "temp" ? c.temperature! : item.kind == "power" ? c.power! : c.fan!
                var gx = item.x
                if item.kind == "fan" && c.fansHeld {
                    // The ring: the fans are under your control.
                    let ring = NSRect(x: item.x, y: midY - 8, width: item.w, height: 16)
                    let path = NSBezierPath(roundedRect: ring.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5)
                    path.lineWidth = 1
                    ink.withAlphaComponent(0.55).setStroke()
                    path.stroke()
                    gx += 3
                }
                let glyphRect = NSRect(x: gx, y: midY - glyphSize / 2, width: glyphSize, height: glyphSize)
                if item.kind != "fan", let symbol = symbol(item.kind == "temp" ? "thermometer.medium" : "bolt.fill") {
                    let s = symbol.size
                    tinted(symbol, ink).draw(in: NSRect(x: glyphRect.midX - s.width / 2, y: glyphRect.midY - s.height / 2,
                                                        width: s.width, height: s.height))
                }
                let text = NSAttributedString(string: readout.text, attributes: [.font: font, .foregroundColor: colour(readout.level) ?? ink])
                let size = text.size()
                text.draw(at: NSPoint(x: glyphRect.maxX + glyphGap, y: midY - size.height / 2 + 0.5))
            }
            for (bar, bx) in zip(c.bars, barXs) {
                let rect = NSRect(x: bx, y: midY - barHeight / 2, width: barWidth, height: barHeight)
                let shape = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
                ink.withAlphaComponent(0.3).setFill()
                shape.fill()
                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                (colour(bar.level) ?? (colourParts ? colour(bar.part) : ink)).setFill()
                // At least a sliver shows above 0, as on the battery.
                let fill = bar.value <= 0.005 ? 0 : max(1, barHeight * min(bar.value, 1))
                NSRect(x: rect.minX, y: rect.minY, width: barWidth, height: fill).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        if let fan = items.first(where: { $0.kind == "fan" }) {
            fanRect = NSRect(x: fan.x + (c.fansHeld ? 3 : 0), y: (height - glyphSize) / 2, width: glyphSize, height: glyphSize)
        }
        image.isTemplate = false
        image.accessibilityDescription = c.spoken
        return (image, fanRect)
    }

    static func symbol(_ name: String, size: CGFloat = 12) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }

    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// The fan glyph: SF Symbols' `fanblades.fill`, four even blades round a hub, so it turns evenly.
    static func fanImage(_ color: NSColor) -> NSImage? {
        // Smaller than the other glyphs: a filled disc of blades looks heavier than a thermometer or a bolt.
        symbol("fanblades.fill", size: 10).map { tinted($0, color) }
    }
}

/// The fan glyph, turning at a pace that follows the faster fan, still when they're off or with Reduce Motion. A layer
/// animation, so it costs next to nothing; changing pace keeps its angle.
final class FanSpinView: NSView {
    private let blades = CALayer()
    private var pace: Float = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(blades)
        blades.speed = 0
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi   // clockwise
        spin.duration = 1
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        blades.add(spin, forKey: "spin")
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blades.frame = bounds
        CATransaction.commit()
        redrawBlades()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redrawBlades()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        redrawBlades()
    }

    /// One turn every 0.35 s at full speed, slower as the fans slow, never slower than one every 1.6 s while they turn.
    func set(fraction: Double) {
        let still = fraction <= 0.01 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let new: Float = still ? 0 : Float(1 / min(max(0.35 / fraction, 0.35), 1.6))
        guard abs(new - pace) > 0.05 * max(pace, 0.1) || (new == 0) != (pace == 0) else { return }
        let now = blades.convertTime(CACurrentMediaTime(), from: nil)
        blades.timeOffset = now
        blades.beginTime = CACurrentMediaTime()
        blades.speed = new
        pace = new
    }

    private func redrawBlades() {
        guard bounds.width > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        var cg: CGImage?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let image = NSImage(size: bounds.size, flipped: false) { rect in
                guard let fan = MacStatsMenuBar.fanImage(.labelColor) else { return false }
                // Centred on the hub, which is the symbol's centre.
                let s = fan.size, k = min(rect.width / s.width, rect.height / s.height, 1)
                fan.draw(in: NSRect(x: rect.midX - s.width * k / 2, y: rect.midY - s.height * k / 2, width: s.width * k, height: s.height * k))
                return true
            }
            var r = NSRect(origin: .zero, size: bounds.size)
            cg = image.cgImage(forProposedRect: &r, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
        }
        blades.contentsScale = scale
        blades.contents = cg
    }
}

/// The status item itself: shown while Mac Stats is on and has something to show, redrawn on every reading.
@MainActor
final class MacStatsStatusItem {
    /// Right-click or Control/Option-click: the app's menu. A plain click opens the stats panel.
    var onMenu: ((NSStatusItem) -> Void)?

    private var item: NSStatusItem?
    private let fanView = FanSpinView(frame: .zero)
    private var holds: [MacStatsMenuBarContent.Part: LevelHold] = [:]
    private var temperatureHold = LevelHold()
    private var fanRect: NSRect?
    private var defaultsObserver: NSObjectProtocol?
    private let panelState = MacStatsPanelState()
    private lazy var panel: MenuBarPanel = {
        let panel = MenuBarPanel { [panelState] _ in AnyView(MacStatsView(stats: .shared, state: panelState)) }
        // Each opening starts on the overview.
        panel.willShow = { [weak self] in self?.panelState.page = .overview }
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

    /// Shows or hides the item and starts or stops the readings to match Settings.
    func apply() {
        // Creating the item writes its position to UserDefaults, which calls this again.
        guard !applying else { return }
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
            if item == nil { build() }
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
            if MacStatsSettings.isEnabled == false { stats.stop() }
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
            button.addSubview(fanView)
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: button, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeFan() }
            }
        }
        self.item = item
    }

    /// Observation fires once per registration, so each change registers again.
    private func watch() {
        withObservationTracking { _ = MacStats.shared.snapshot } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, MacStats.shared.running else { return }
                self.redraw()
                self.watch()
            }
        }
    }

    private func redraw() {
        guard let button = item?.button else { return }
        let s = MacStats.shared.snapshot
        let warn = MacStatsSettings.on(MacStatsSettings.warnings)
        var levels: [MacStatsMenuBarContent.Part: StatLevel] = [:]
        for part in MacStatsMenuBarContent.Part.allCases {
            var hold = holds[part] ?? LevelHold()
            levels[part] = warn ? hold.update(MacStatsMenuBarContent.rawLevel(part, s), at: s.date) : .normal
            holds[part] = hold
        }
        let celsius = MacStatsMenuBarContent.celsius(s, .current)
        let tempLevel = warn ? temperatureHold.update(celsius.map { StatLevel(celsius: $0) } ?? .normal, at: s.date) : .normal
        let content = MacStatsMenuBarContent.make(s, levels: levels, temperatureLevel: tempLevel,
                                                  fahrenheit: Locale.current.measurementSystem == .us)
        let (image, fan) = MacStatsMenuBar.image(content, colourParts: MacStatsSettings.on(MacStatsSettings.colourParts))
        button.image = image
        button.toolTip = content.spoken
        button.setAccessibilityLabel(content.spoken)
        fanRect = fan
        fanView.isHidden = fan == nil
        fanView.set(fraction: content.fanFraction)
        placeFan()
    }

    /// Puts the fan over its gap in the image, which the button draws centred.
    private func placeFan() {
        guard let button = item?.button, let image = button.image, let fanRect else { return }
        let origin = NSPoint(x: (button.bounds.width - image.size.width) / 2, y: (button.bounds.height - image.size.height) / 2)
        let y = button.isFlipped ? origin.y + image.size.height - fanRect.maxY : origin.y + fanRect.minY
        fanView.frame = NSRect(x: (origin.x + fanRect.minX).rounded(), y: y.rounded(), width: fanRect.width, height: fanRect.height)
    }

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
