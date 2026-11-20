import SwiftUI

/// The battery page, opened from the battery chip in the panel's header: the charge and what it's doing, then four
/// glass tiles (maximum capacity, cycles, the charger or the power draw, time to full or left), and the capacity in
/// mAh with a link to Battery settings. The numbers refresh every 3 s while it's open (`PowerMonitor.watchDetails`).
struct BatteryPage: View {
    let power: PowerMonitor

    var body: some View {
        let s = power.state, d = power.details
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                BatteryGlyph(percent: s.percent, tint: Self.tint(s), bolt: s.charging || s.onAC, limit: d.chargeLimit)
                    .frame(width: 46, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    RollingNumber(value: Double(s.percent) / 100, suffix: "%", size: 28)
                        .foregroundStyle(Color.isletText)
                    Text(Self.status(s, limit: d.chargeLimit)).font(.system(size: 11)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                }
                Spacer()
                if let limit = d.chargeLimit {
                    // macOS lets only System Settings change the limit, so this opens it there.
                    Button { SystemSettings.open(SystemSettings.battery) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "battery.75percent").font(.system(size: 10, weight: .semibold))
                            Text("Limit \(limit)%").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.isletTertiary)
                        }
                        .foregroundStyle(Color.isletText)
                        .padding(.horizontal, 9).frame(height: 22).background(IsletCard(shape: Capsule()))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Charging stops at \(limit)%. Change it in Battery settings.")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 60)
            .padding(.top, 4)

            HStack(spacing: 10) {
                // What System Settings says when we have it; our own full-charge vs design ratio until then.
                if let h = power.reportedHealth {
                    StatTile(label: "CAPACITY", value: "\(h.percent)%", detail: h.condition)
                } else {
                    StatTile(label: "CAPACITY", value: d.health.map { "\($0)%" } ?? "–",
                             detail: d.health.map { $0 >= 80 ? "Normal" : "Worn" } ?? "Maximum")
                }
                StatTile(label: "CYCLES", value: d.cycles.map { "\($0)" } ?? "–",
                         detail: d.designCycles.map { "of \($0)" } ?? "Charge cycles")
                if s.onAC {
                    StatTile(label: "CHARGER", value: d.adapterWatts.map { "\($0) W" } ?? "On",
                             detail: Self.chargeDetail(s, d))
                } else {
                    StatTile(label: "USING", value: Self.watts(d.systemWatts), detail: "Whole Mac")
                }
                lastTile(s, d)
            }
            .padding(.top, 10)

            EnergyModeRow(controller: .shared, onAC: s.onAC)
                .padding(.top, 12)
                .onChange(of: s.onAC) { PowerModeController.shared.refresh() }

            Spacer(minLength: 0)
            HStack {
                if let now = d.currentMAh, let full = d.fullMAh {
                    Text("\(now.formatted()) of \(full.formatted()) mAh").font(.system(size: 10)).foregroundStyle(Color.isletTertiary)
                        .monospacedDigit()
                }
                Spacer()
                SettingsLink(title: "Battery Settings…", pane: SystemSettings.battery)
            }
            .padding(.leading, 8).padding(.bottom, 4)
        }
    }

    /// Never the same as the tile beside it: the time to full or left (macOS's estimate, or worked out from the energy
    /// left and the power flowing), else what the charger is powering, else the energy stored.
    @ViewBuilder private func lastTile(_ s: PowerMonitor.State, _ d: PowerMonitor.Details) -> some View {
        let target = d.chargeLimit ?? 100
        if s.charging, let m = Self.minutesToFull(d, target: target) ?? s.minutesToFull {
            // To the charge limit when there is one (macOS's own estimate is to 100%).
            StatTile(label: target < 100 ? "UNTIL \(target)%" : "UNTIL FULL", value: Self.duration(m),
                     detail: target < 100 ? "Charge limit" : "At this rate")
        } else if s.onAC, let limit = d.chargeLimit, s.percent >= limit - 1 {
            StatTile(label: "CHARGED", value: "\(limit)%", detail: "Holding at limit")
        } else if !s.onAC, let m = s.minutesToEmpty ?? Self.minutesLeft(d) {
            StatTile(label: "TIME LEFT", value: Self.duration(m), detail: s.minutesToEmpty == nil ? "At this rate" : "Estimated")
        } else if s.onAC, d.systemWatts != nil {
            StatTile(label: "USING", value: Self.watts(d.systemWatts), detail: "From the charger")
        } else {
            StatTile(label: "ENERGY", value: d.storedWh.map { "\(Int($0.rounded())) Wh" } ?? "–",
                     detail: d.fullWh.map { "of \(Int($0.rounded())) Wh" } ?? "Stored")
        }
    }

    /// Energy left over what the Mac is drawing now.
    private static func minutesLeft(_ d: PowerMonitor.Details) -> Int? {
        guard let wh = d.storedWh, let w = d.systemWatts, w > 0.5 else { return nil }
        return Int((wh / w * 60).rounded())
    }

    /// Energy still to go in, up to `target` percent, over what's flowing into the battery now.
    private static func minutesToFull(_ d: PowerMonitor.Details, target: Int) -> Int? {
        guard let now = d.storedWh, let full = d.fullWh, let w = d.batteryWatts, w > 0.5 else { return nil }
        let goal = full * Double(target) / 100
        guard goal > now else { return nil }
        return Int(((goal - now) / w * 60).rounded())
    }

    private static func tint(_ s: PowerMonitor.State) -> Color {
        if s.charging || s.charged { return .isletGreen }
        if !s.onAC && s.percent <= 20 { return .isletRed }
        return .isletText
    }

    static func status(_ s: PowerMonitor.State, limit: Int? = nil) -> String {
        if s.charged { return "Fully charged" }
        if let limit, s.onAC, s.percent >= limit - 1 { return "Charged to your \(limit)% limit" }
        if s.charging { return limit != nil ? "Charging to \(limit!)%" : s.minutesToFull.map { "Charging · \(duration($0)) until full" } ?? "Charging" }
        if s.onAC { return "Plugged in, not charging" }
        return s.minutesToEmpty.map { "On battery · \(duration($0)) left" } ?? "On battery"
    }

    private static func chargeDetail(_ s: PowerMonitor.State, _ d: PowerMonitor.Details) -> String {
        if s.charging, let w = d.batteryWatts, w > 0.5 { return "\(watts(w)) to battery" }
        return s.charging ? "Charging" : "Not charging"
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static func watts(_ w: Double?) -> String {
        guard let w else { return "–" }
        return w < 10 ? String(format: "%.1f W", w) : "\(Int(w.rounded())) W"
    }
}

/// Energy Mode for the source in use: Low Power, Automatic, High Power. The first change asks for the admin password
/// once (`PowerModeController`).
private struct EnergyModeRow: View {
    let controller: PowerModeController
    var onAC: Bool

    private static let order: [(PowerModeController.Mode, String, String, Color)] = [
        (.low, "Low Power", "tortoise.fill", Color(hex: 0xFFD60A)),
        (.automatic, "Automatic", "gauge.with.dots.needle.50percent", Color.isletText),
        (.high, "High Power", "hare.fill", Color(hex: 0xFF9F0A)),
    ]

    var body: some View {
        if let mode = controller.mode {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Energy Mode").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText)
                    if let e = controller.error {
                        Text(e).font(.system(size: 10)).foregroundStyle(Color.isletRedText).lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        Text(onAC ? "On power adapter" : "On battery").font(.system(size: 10)).foregroundStyle(Color.isletSecondary)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    ForEach(Self.order, id: \.0) { item in
                        let selected = item.0 == mode
                        Button { controller.set(item.0, onAC: onAC) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.2).font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(selected ? item.3 : Color.isletTertiary)
                                Text(item.1).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(selected ? Color.isletText : Color.isletSecondary)
                            }
                            .padding(.horizontal, 10).frame(height: 26)
                            .background { if selected { IsletCard(shape: Capsule()) } }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .opacity(controller.busy ? 0.6 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: mode)
            }
            .padding(.horizontal, 8)
        }
    }
}

/// One stat on the battery page: a small caps label, the number, a line under it. Glass, like the control tiles.
private struct StatTile: View {
    var label: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.7).foregroundStyle(Color.isletTertiary)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color.isletText).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(detail).font(.system(size: 10)).foregroundStyle(Color.isletSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72)
        .background(IsletCard(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// A battery drawn to scale: outline, the charge as a fill, a nub, and a bolt while plugged in.
struct BatteryGlyph: View {
    var percent: Int
    var tint: Color
    var bolt: Bool
    /// A tick in the outline at the charge limit.
    var limit: Int?

    var body: some View {
        GeometryReader { geo in
            let nub = geo.size.width * 0.07
            let w = geo.size.width - nub - 1.5, h = geo.size.height
            let inset: CGFloat = 2.5
            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: h * 0.3, style: .continuous)
                        .stroke(Color.isletText.opacity(0.45), lineWidth: 1.4)
                    RoundedRectangle(cornerRadius: h * 0.3 - inset, style: .continuous)
                        .fill(tint)
                        .frame(width: max(2, (w - 2 * inset) * CGFloat(min(max(percent, 0), 100)) / 100))
                        .padding(inset)
                        .animation(.levelGlide, value: percent)
                    if let limit {
                        Rectangle().fill(Color.isletText.opacity(0.6)).frame(width: 1.2, height: h + 4)
                            .offset(x: inset + (w - 2 * inset) * CGFloat(limit) / 100 - 0.6)
                    }
                    if bolt {
                        Image(systemName: "bolt.fill").font(.system(size: h * 0.62, weight: .bold))
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .frame(width: w, height: h)
                    }
                }
                .frame(width: w, height: h)
                RoundedRectangle(cornerRadius: 1.5).fill(Color.isletText.opacity(0.45)).frame(width: nub, height: h * 0.36)
            }
        }
    }
}
