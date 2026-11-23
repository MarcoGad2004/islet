import Charts
import SwiftUI

/// The battery icon's stats (DESIGN.md "Menu bar battery"): the charge and what it's doing, the battery's condition,
/// the charge over the last 12 hours and where the power is going. The numbers refresh every second while it's open
/// (`PowerMonitor.watchDetails`).
struct BatteryStatsView: View {
    let power: PowerMonitor
    /// Opens the island's control center, for when the icon's click shows these stats instead.
    var openControls: () -> Void

    var body: some View {
        let s = power.state, d = power.details
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Battery").font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(s.percent)%").font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Color.isletText)
            .padding(.bottom, 8)

            VStack(spacing: 7) {
                ForEach(Self.chargeRows(s, d, unplugged: power.history.unpluggedAt), id: \.0) { row($0.0, $0.1) }
            }
            divider
            VStack(spacing: 7) {
                row("Power Source", s.onAC ? (d.adapterName.map { "Power Adapter · \($0)" } ?? "Power Adapter") : "Battery Power")
                row("Cycle Count", d.cycles.map { "\($0)" } ?? "–")
                row("Temperature", d.temperature.map(Self.temperature) ?? "–")
                row("Battery Health", health(d))
                if d.lowPower { row("Low Power Mode", "On") }
            }
            divider
            Text("Last 12 hours").font(.system(size: 13)).foregroundStyle(Color.isletSecondary)
            ChargeChart(samples: power.history.recent(hours: 12, current: s))
                .frame(height: 120)
                .padding(.top, 8)
            divider
            Text("Power distribution").font(.system(size: 13)).foregroundStyle(Color.isletSecondary)
            PowerFlow(state: s, details: d).padding(.top, 8)
            divider
            HStack {
                Button(action: openControls) {
                    HStack(spacing: 5) {
                        Image(systemName: "switch.2").font(.system(size: 10, weight: .semibold))
                        Text("Controls").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.isletText)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(IsletCard(shape: Capsule()))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Open Dynamic Peninsula's control center")
                Spacer()
                SettingsLink(title: "Battery Settings…", pane: SystemSettings.battery)
            }
        }
        .padding(16)
        .frame(width: 300)
        .animation(.easeOut(duration: 0.3), value: s.percent)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.vertical, 12)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.isletSecondary)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Color.isletText).monospacedDigit().lineLimit(1)
        }
        .font(.system(size: 13))
    }

    private func health(_ d: PowerMonitor.Details) -> String {
        if let h = power.reportedHealth { return h.condition == "Normal" ? "\(h.percent)%" : "\(h.percent)% · \(h.condition)" }
        return d.health.map { "\($0)%" } ?? "–"
    }

    /// What the charge is doing: the time to full or left, and how long since the charger came out.
    static func chargeRows(_ s: PowerMonitor.State, _ d: PowerMonitor.Details, unplugged: Date?, now: Date = Date()) -> [(String, String)] {
        var rows: [(String, String)] = []
        if s.charged {
            rows.append(("Status", "Fully Charged"))
        } else if let limit = d.chargeLimit, s.onAC, s.percent >= limit - 1 {
            rows.append(("Status", "Holding at \(limit)%"))
        } else if s.charging, let limit = d.chargeLimit {
            // To the limit, not to 100% (macOS's own estimate is to full).
            rows.append(("Time to \(limit)%", BatteryPage.minutesToFull(d, target: limit).map(duration) ?? "Calculating…"))
        } else if s.charging {
            rows.append(("Time to Full", (BatteryPage.minutesToFull(d, target: 100) ?? s.minutesToFull).map(duration) ?? "Calculating…"))
        } else if s.onAC {
            rows.append(("Status", "Not Charging"))
        } else {
            rows.append(("Time Left", s.minutesToEmpty.map(duration) ?? "Calculating…"))
        }
        if let limit = d.chargeLimit { rows.append(("Charge Limit", "\(limit)%")) }
        if !s.onAC, let unplugged {
            rows.append(("Since Unplugged", duration(max(0, Int(now.timeIntervalSince(unplugged) / 60)))))
        }
        return rows
    }

    /// "3 hr, 7 min", as macOS writes it.
    static func duration(_ minutes: Int) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .short
        return f.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }

    /// In the units the Mac's region uses (°F in the US).
    static func temperature(_ celsius: Double) -> String {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 1
        f.numberFormatter.minimumFractionDigits = 1
        return f.string(from: Measurement(value: celsius, unit: UnitTemperature.celsius))
    }
}

/// The charge over the last 12 hours: a green line over a faint fill, with the hours along the bottom.
private struct ChargeChart: View {
    let samples: [BatteryHistory.Sample]

    var body: some View {
        let end = Date(), start = end.addingTimeInterval(-12 * 3600)
        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, s in marks(s) }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 10)).foregroundStyle(Color.isletSecondary) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel(format: .dateTime.hour()).font(.system(size: 10)).foregroundStyle(Color.isletSecondary)
            }
        }
        .overlay {
            if samples.count < 2 {
                Text("Dynamic Peninsula is still recording").font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
            }
        }
    }
}

extension ChargeChart {
    private static let fade = LinearGradient(colors: [Color.isletGreen.opacity(0.25), Color.isletGreen.opacity(0)],
                                             startPoint: .top, endPoint: .bottom)

    @ChartContentBuilder private func marks(_ s: BatteryHistory.Sample) -> some ChartContent {
        AreaMark(x: .value("Time", s.time), yStart: .value("Start", 0), yEnd: .value("Charge", s.percent))
            .foregroundStyle(Self.fade)
        LineMark(x: .value("Time", s.time), y: .value("Charge", s.percent))
            .foregroundStyle(Color.isletGreen)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

/// Where the power is flowing right now, worked out from the charger's input, the battery's current and the Mac's
/// draw. Each flow is a line that runs only while power moves along it, as thick as its share, with dashes drifting
/// the way the power goes.
struct PowerFlows: Equatable {
    var chargerConnected: Bool
    var chargerToMac: Double = 0
    var chargerToBattery: Double = 0
    var batteryToMac: Double = 0
    var mac: Double?
    var charger: Double?

    /// Under this many watts a flow counts as stopped.
    static let still = 0.3

    /// The flows come from the Mac's draw and the charger's input (read together from the SMC); the battery's share
    /// is what's left over, so the three always add up. They're rounded alike before the totals are made from them, so
    /// the labels add up too.
    init(state: PowerMonitor.State, details d: PowerMonitor.Details) {
        chargerConnected = state.onAC
        let system = max(0, d.systemWatts ?? -(d.batteryWatts ?? 0))
        if state.onAC {
            let input = d.adapterInWatts ?? (system + max(0, d.batteryWatts ?? 0))
            if input >= system {
                chargerToMac = system
                chargerToBattery = input - system
            } else {
                // A charger too weak for the load: the battery makes up the rest.
                chargerToMac = input
                batteryToMac = system - input
            }
        } else {
            batteryToMac = system
        }
        let step = chargerToMac + chargerToBattery + batteryToMac >= 10 ? 1.0 : 0.1
        func round(_ w: Double) -> Double { w < Self.still ? 0 : (w / step).rounded() * step }
        chargerToMac = round(chargerToMac)
        chargerToBattery = round(chargerToBattery)
        batteryToMac = round(batteryToMac)
        mac = d.systemWatts == nil && d.batteryWatts == nil ? nil : chargerToMac + batteryToMac
        charger = state.onAC ? chargerToMac + chargerToBattery : nil
    }

    var total: Double { max(chargerToMac + chargerToBattery + batteryToMac, 1) }
}

struct PowerFlow: View {
    let state: PowerMonitor.State
    let details: PowerMonitor.Details
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = FlowClock()

    private static let chargerTint = Color.isletGreen
    private static let batteryTint = Color(hex: 0xFFD60A)
    private static let node: CGFloat = 38
    /// Space above the nodes for the charger-to-battery arc over the Mac.
    private static let arcRoom: CGFloat = 16

    private func batteryTint(_ f: PowerFlows) -> Color {
        f.batteryToMac > PowerFlows.still ? Self.batteryTint : f.chargerToBattery > PowerFlows.still ? Self.chargerTint : Color.isletSecondary
    }

    var body: some View {
        let f = PowerFlows(state: state, details: details)
        TimelineView(.animation(paused: reduceMotion)) { time in
            let phases = reduceMotion ? [0, 0, 0] : clock.tick(time.date, watts: [f.chargerToMac, f.chargerToBattery, f.batteryToMac])
            GeometryReader { geo in
                let w = geo.size.width
                let r = Self.node / 2
                let y = Self.arcRoom + r
                let chargerAt = CGPoint(x: r + 14, y: y)
                let macAt = CGPoint(x: w / 2, y: y)
                let batteryAt = CGPoint(x: w - r - 14, y: y)
                let toMacFromCharger = Self.line(from: CGPoint(x: chargerAt.x + r + 3, y: y), to: CGPoint(x: macAt.x - r - 3, y: y))
                let toMacFromBattery = Self.line(from: CGPoint(x: batteryAt.x - r - 3, y: y), to: CGPoint(x: macAt.x + r + 3, y: y))
                let toBattery = Self.arc(from: chargerAt, to: batteryAt, r: r)
                ZStack {
                    // Faint rails for every route, so the diagram keeps its shape when a flow stops.
                    rail(toMacFromCharger)
                    rail(toMacFromBattery)
                    rail(toBattery)
                    flow(toMacFromCharger, f.chargerToMac, f.total, Self.chargerTint, phases[0])
                    flow(toBattery, f.chargerToBattery, f.total, Self.chargerTint, phases[1])
                    flow(toMacFromBattery, f.batteryToMac, f.total, Self.batteryTint, phases[2])

                    nodeView("powerplug.portrait.fill", tint: Self.chargerTint, active: f.chargerConnected)
                        .position(chargerAt)
                    nodeView("laptopcomputer", tint: Color.isletText, active: true)
                        .position(macAt)
                    nodeView(batterySymbol, tint: batteryTint(f), active: true)
                        .position(batteryAt)
                    label("Charger", f.chargerConnected ? BatteryPage.watts(f.charger) : "Unplugged", lit: f.chargerConnected)
                        .position(x: chargerAt.x, y: y + r + 18)
                    label("Mac", BatteryPage.watts(f.mac), lit: true)
                        .position(x: macAt.x, y: y + r + 18)
                    label("Battery", batteryText(f), lit: true)
                        .position(x: batteryAt.x, y: y + r + 18)
                }
            }
        }
        .frame(height: Self.arcRoom + Self.node + 36)
        // Every change of state glides: lines run out or draw back, thicknesses and colours ease.
        .animation(.spring(response: 0.7, dampingFraction: 0.9), value: f)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(f))
    }

    private var batterySymbol: String {
        let p = state.percent
        return p >= 88 ? "battery.100percent" : p >= 63 ? "battery.75percent" : p >= 38 ? "battery.50percent" : p >= 13 ? "battery.25percent" : "battery.0percent"
    }

    private func batteryText(_ f: PowerFlows) -> String {
        if f.batteryToMac > PowerFlows.still { return "\(BatteryPage.watts(f.batteryToMac)) out" }
        if f.chargerToBattery > PowerFlows.still { return "\(BatteryPage.watts(f.chargerToBattery)) in" }
        return "Resting"
    }

    static func summary(_ f: PowerFlows) -> String {
        var parts: [String] = []
        if f.chargerToMac > PowerFlows.still { parts.append("charger to Mac \(BatteryPage.watts(f.chargerToMac))") }
        if f.chargerToBattery > PowerFlows.still { parts.append("charger to battery \(BatteryPage.watts(f.chargerToBattery))") }
        if f.batteryToMac > PowerFlows.still { parts.append("battery to Mac \(BatteryPage.watts(f.batteryToMac))") }
        return parts.isEmpty ? "No power flowing" : parts.joined(separator: ", ")
    }

    private func nodeView(_ symbol: String, tint: Color, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active ? tint : Color.isletTertiary)
            .frame(width: Self.node, height: Self.node)
            .background(IsletCard(shape: Circle()))
            .overlay(Circle().stroke(active ? tint.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1))
            .opacity(active ? 1 : 0.55)
    }

    private func label(_ title: String, _ value: String, lit: Bool) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.isletTertiary)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(lit ? Color.isletText : Color.isletTertiary)
                .contentTransition(.numericText())
        }
        .frame(width: 84)
        .animation(.easeOut(duration: 0.3), value: value)
    }

    private func rail(_ path: Path) -> some View {
        path.stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// A glowing line with dashes drifting along it; thicker for a bigger share of the power. Lighting up, it runs out
    /// from where the power comes from; going dark, it draws back and fades. Its thickness glides as the share changes.
    private func flow(_ path: Path, _ watts: Double, _ total: Double, _ tint: Color, _ phase: CGFloat) -> some View {
        let on = watts > PowerFlows.still
        let width = 2 + 3 * CGFloat(min(1, watts / total))
        return ZStack {
            FlowStroke(path: path, width: width, reach: on ? 1 : 0, phase: 0, dashed: false)
                .fill(tint.opacity(0.28))
            FlowStroke(path: path, width: width, reach: on ? 1 : 0, phase: -phase, dashed: true)
                .fill(tint)
                .shadow(color: tint.opacity(0.6), radius: 3)
        }
        .opacity(on ? 1 : 0)
    }

    /// From the charger up over the Mac and down into the battery.
    private static func arc(from a: CGPoint, to b: CGPoint, r: CGFloat) -> Path {
        Path { p in
            let start = CGPoint(x: a.x + r * 0.55, y: a.y - r * 0.85), end = CGPoint(x: b.x - r * 0.55, y: b.y - r * 0.85)
            p.move(to: start)
            p.addCurve(to: end, control1: CGPoint(x: start.x + 30, y: 0), control2: CGPoint(x: end.x - 30, y: 0))
        }
    }

    private static func line(from a: CGPoint, to b: CGPoint) -> Path {
        Path { p in
            p.move(to: a)
            p.addLine(to: b)
        }
    }
}

/// How far each line's dashes have drifted. The speed follows the line's watts (faster for more power, on a square
/// root so it never races) and eases toward a new reading; each line keeps its own running distance so a change of
/// speed never makes its dashes jump.
@MainActor
final class FlowClock {
    private var last: Date?
    private var speeds: [Double] = []
    private var phases: [Double] = []

    /// Points per second: 8 when barely moving, 30 at 100 W.
    nonisolated static func speed(_ watts: Double) -> Double { 8 + 22 * min(1, (max(0, watts) / 100).squareRoot()) }

    func tick(_ now: Date, watts: [Double]) -> [CGFloat] {
        let targets = watts.map(Self.speed)
        if speeds.count != targets.count { speeds = targets; phases = Array(repeating: 0, count: targets.count) }
        let dt = min(0.1, max(0, last.map { now.timeIntervalSince($0) } ?? 0))
        last = now
        for i in targets.indices {
            speeds[i] += (targets[i] - speeds[i]) * min(1, dt * 2.5) // about a second to settle
            phases[i] = (phases[i] + speeds[i] * dt).truncatingRemainder(dividingBy: 13 * 1000) // 13 = one dash and gap
        }
        return phases.map { CGFloat($0) }
    }
}

/// A flow line as a filled outline, so its thickness and how far along the line it reaches animate (a stroke's width
/// doesn't). The dashes' drift (`phase`) comes from `FlowClock`, not the animation.
private struct FlowStroke: Shape {
    var path: Path
    var width: CGFloat
    var reach: CGFloat
    var phase: CGFloat
    var dashed: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, reach) }
        set { width = newValue.first; reach = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        guard reach > 0.001 else { return Path() }
        let style = StrokeStyle(lineWidth: width, lineCap: .round, dash: dashed ? [4, 9] : [], dashPhase: phase)
        return path.trimmedPath(from: 0, to: min(1, reach)).strokedPath(style)
    }
}

