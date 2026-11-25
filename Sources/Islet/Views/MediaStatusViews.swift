import SwiftUI

// The Now Playing page's two new strips (DESIGN.md "Media", "Expanded (media playing)"): small pills that say what is
// on (Wi-Fi, Bluetooth, AirDrop, Mirroring, battery) and a row of media buttons (shuffle, back 15 s, forward 15 s, repeat).

/// Lays the status pills out in one row: the ones marked `fixed` keep their natural width; the others get what they
/// need, shortest first, and share what is left, so a long network name gives way before a short one does. When
/// everything fits, the extra room is spread over the flexible pills so the row spans its width.
struct PillRow: Layout {
    var spacing: CGFloat = 5

    struct Fixed: LayoutValueKey { static let defaultValue = false }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 468, height: 22)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = Self.widths(ideal: subviews.map { $0.sizeThatFits(.unspecified).width },
                                 fixed: subviews.map { $0[Fixed.self] }, total: bounds.width, spacing: spacing)
        var x = bounds.minX
        for (view, w) in zip(subviews, widths) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }

    /// The width of each pill. Exposed for the tests.
    static func widths(ideal: [CGFloat], fixed: [Bool], total: CGFloat, spacing: CGFloat) -> [CGFloat] {
        var out = ideal
        let room = total - spacing * CGFloat(max(ideal.count - 1, 0))
        var left = room - zip(ideal, fixed).filter { $0.1 }.map(\.0).reduce(0, +)
        var flex = ideal.indices.filter { !fixed[$0] }.sorted { ideal[$0] < ideal[$1] }
        while let i = flex.first {
            let share = left / CGFloat(flex.count)
            if ideal[i] <= share { out[i] = ideal[i]; left -= ideal[i]; flex.removeFirst() }
            else { for j in flex { out[j] = max(share, 0) }; return out }
        }
        // Everything fits: spread the room that is left over the flexible pills.
        let flexAll = ideal.indices.filter { !fixed[$0] }
        if !flexAll.isEmpty, left > 0 { for j in flexAll { out[j] += left / CGFloat(flexAll.count) } }
        return out
    }
}

/// One status pill: an icon and a word or name. Blue when on, grey when off; the battery is green (red when low).
struct StatusPill<Icon: View>: View {
    enum Look { case on, off, battery, low }
    var text: String
    var look: Look
    var help: String
    var action: () -> Void
    @ViewBuilder var icon: () -> Icon
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                icon().foregroundStyle(iconColor)
                Text(text).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, 7).frame(maxHeight: .infinity)
            .background(Capsule().fill(fill.opacity(hover ? 1.4 : 1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: look)
    }

    private var fill: Color {
        switch look {
        case .on: Color(hex: 0x0A84FF).opacity(0.22)
        case .off: Color.white.opacity(0.08)
        case .battery: Color.isletGreen.opacity(0.2)
        case .low: Color.isletRed.opacity(0.22)
        }
    }
    private var textColor: Color { look == .off ? .isletTertiary : look == .low ? .isletRedText : .white }
    private var iconColor: Color {
        switch look {
        case .on: Color(hex: 0x3D9BFF)
        case .off: .isletTertiary
        case .battery: .isletGreen
        case .low: .isletRedText
        }
    }
}

/// The strip under the header: Wi-Fi, Bluetooth, AirDrop, Mirroring and the battery, each opening its own page.
struct MediaStatusStrip: View {
    let store: IslandStore

    var body: some View {
        PillRow {
            if let wifi = store.wifi {
                let joined = wifi.isConnected
                let name = wifi.hotspot ? "Hotspot" : (wifi.ssid ?? "Wi-Fi")
                StatusPill(text: joined ? name : "Wi-Fi", look: joined ? .on : .off,
                           help: joined ? "Wi-Fi: \(name)" : (wifi.powerOn ? "Wi-Fi: not connected" : "Wi-Fi: off"),
                           action: { open(.wifi) }) {
                    Image(systemName: !joined ? "wifi.slash" : wifi.hotspot ? "personalhotspot" : "wifi").font(.system(size: 10, weight: .semibold))
                }
            }
            if let bt = store.bluetooth {
                let connected = bt.devices.filter(\.connected)
                let text = !bt.powerOn ? "Bluetooth" : connected.count == 1 ? connected[0].name : connected.count > 1 ? "\(connected.count) devices" : "Bluetooth"
                StatusPill(text: text, look: bt.powerOn ? .on : .off,
                           help: !bt.powerOn ? "Bluetooth: off" : connected.isEmpty ? "Bluetooth: on" : "Bluetooth: " + connected.map(\.name).joined(separator: ", "),
                           action: { open(.bluetooth) }) {
                    BluetoothGlyph().frame(width: 7, height: 10)
                }
            }
            if let ad = store.airdrop {
                StatusPill(text: ad.mode.status, look: ad.mode == .off ? .off : .on, help: "AirDrop: \(ad.mode.status)",
                           action: { ad.openAirDrop(); store.collapse() }) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 10, weight: .semibold))
                }
                .layoutValue(key: PillRow.Fixed.self, value: true)
            }
            let ipad = store.sidecar?.devices.first(where: \.connected)
            StatusPill(text: ipad?.name ?? "Mirroring", look: ipad == nil ? .off : .on,
                       help: ipad.map { "Mirroring: \($0.name)" } ?? "Mirroring: not connected", action: { open(.mirroring) }) {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 9.5, weight: .semibold))
            }
            if let power = store.power, power.state.hasBattery {
                let s = power.state
                let low = s.percent <= 20 && !s.charging && !s.onAC
                StatusPill(text: "\(s.percent)%", look: low ? .low : .battery,
                           help: s.charged ? "Fully charged" : s.charging ? "Charging, \(s.percent)%" : s.onAC ? "Plugged in, \(s.percent)%" : "On battery, \(s.percent)%",
                           action: { open(.battery) }) {
                    Image(systemName: s.charging || s.onAC ? "bolt.fill" : "battery.50").font(.system(size: 9.5, weight: .semibold))
                }
                .layoutValue(key: PillRow.Fixed.self, value: true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.wifi?.ssid)
    }

    /// A pill's page lives on the controls pages: go there and open it.
    private func open(_ detail: ControlDetail) {
        store.showControlsPage()
        store.setControlDetail(detail)
    }
}

/// The media buttons in a card of equal columns. A music app gets shuffle, back, forward and repeat; a browser, whose
/// media session answers neither shuffle nor repeat, gets back and forward (10 s, like a video's own skip) only.
struct MediaControlRow: View {
    let media: MediaInfo
    let monitor: MediaMonitor

    var body: some View {
        let browser = media.isBrowser
        let n = Int(media.skipSeconds)
        HStack(spacing: 0) {
            if !browser {
                MediaRowButton(symbol: "shuffle", caption: "Shuffle", on: media.shuffle) { monitor.setShuffle(!media.shuffle) }
            }
            MediaRowButton(symbol: "gobackward.\(n)", caption: "Back \(n) s", on: false) { monitor.skip(seconds: -media.skipSeconds) }
            MediaRowButton(symbol: "goforward.\(n)", caption: "Forward \(n) s", on: false) { monitor.skip(seconds: media.skipSeconds) }
            if !browser {
                MediaRowButton(symbol: media.repeatMode == 2 ? "repeat.1" : "repeat", caption: "Repeat", on: media.repeatMode > 1) { monitor.cycleRepeat() }
            }
        }
        .padding(.horizontal, browser ? 100 : 8)
        .frame(maxHeight: .infinity)
        .background(IsletCard(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .animation(.easeOut(duration: 0.2), value: browser)
    }
}

private struct MediaRowButton: View {
    var symbol: String
    var caption: String
    var on: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 20, weight: .regular)).frame(height: 24)
                Text(caption).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(on ? Color.isletGreen : hover ? Color.isletText : Color.isletSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: on)
        .help(caption)
    }
}
