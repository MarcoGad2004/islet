import Charts
import SwiftUI

/// The battery icon's stats (DESIGN.md "Menu bar battery"): the charge and what it's doing, the battery's condition,
/// the charge over the last 12 hours and where the power is going. The numbers refresh every 3 s while it's open
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
                if let limit = d.chargeLimit { row("Charge Limit", "\(limit)%") }
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
                .help("Open Islet's control center")
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
        } else if s.charging {
            rows.append(("Time to Full", s.minutesToFull.map(duration) ?? "Calculating…"))
        } else if s.onAC {
            rows.append(("Status", "Not Charging"))
        } else {
            rows.append(("Time Left", s.minutesToEmpty.map(duration) ?? "Calculating…"))
        }
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
                Text("Islet is still recording").font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
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

/// Where the power goes: from the battery to the Mac, or from the charger to the Mac and the battery.
private struct PowerFlow: View {
    let state: PowerMonitor.State
    let details: PowerMonitor.Details

    var body: some View {
        let d = details
        HStack(spacing: 8) {
            if state.onAC {
                pill("powerplug.portrait.fill", d.adapterInWatts ?? sum(d.systemWatts, max(0, d.batteryWatts ?? 0)))
                arrow
                VStack(spacing: 6) {
                    pill("laptopcomputer", d.systemWatts)
                    if let b = d.batteryWatts, b > 0.1 { pill("battery.75percent", b) }
                }
            } else {
                pill("battery.75percent", d.batteryWatts.map { -$0 } ?? d.systemWatts)
                arrow
                pill("laptopcomputer", d.systemWatts)
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletTertiary)
    }

    private func sum(_ a: Double?, _ b: Double) -> Double? { a.map { $0 + b } }

    private func pill(_ symbol: String, _ watts: Double?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Color.isletSecondary)
            Text(BatteryPage.watts(watts.map { max(0, $0) })).font(.system(size: 13, weight: .medium)).monospacedDigit()
                .foregroundStyle(Color.isletText)
        }
        .frame(maxWidth: .infinity).frame(height: 34)
        .background(IsletCard(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)))
    }
}
