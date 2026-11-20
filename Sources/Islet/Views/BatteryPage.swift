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
                BatteryGlyph(percent: s.percent, tint: Self.tint(s), bolt: s.charging || s.onAC)
                    .frame(width: 46, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    RollingNumber(value: Double(s.percent) / 100, suffix: "%", size: 28)
                        .foregroundStyle(Color.isletText)
                    Text(Self.status(s)).font(.system(size: 11)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                }
                Spacer()
                if d.lowPower {
                    Label("Low Power", systemImage: "bolt.badge.automatic.fill")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0xFFD60A))
                        .padding(.horizontal, 9).frame(height: 22).background(IsletCard(shape: Capsule()))
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
        if s.charging, let m = s.minutesToFull ?? Self.minutesToFull(d) {
            StatTile(label: "UNTIL FULL", value: Self.duration(m), detail: s.minutesToFull == nil ? "At this rate" : "Estimated")
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

    /// Energy still to go in over what's flowing into the battery now.
    private static func minutesToFull(_ d: PowerMonitor.Details) -> Int? {
        guard let now = d.storedWh, let full = d.fullWh, let w = d.batteryWatts, w > 0.5, full > now else { return nil }
        return Int(((full - now) / w * 60).rounded())
    }

    private static func tint(_ s: PowerMonitor.State) -> Color {
        if s.charging || s.charged { return .isletGreen }
        if !s.onAC && s.percent <= 20 { return .isletRed }
        return .isletText
    }

    static func status(_ s: PowerMonitor.State) -> String {
        if s.charged { return "Fully charged" }
        if s.charging { return s.minutesToFull.map { "Charging · \(duration($0)) until full" } ?? "Charging" }
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
