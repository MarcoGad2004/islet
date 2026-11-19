import CoreGraphics
import SwiftUI

/// The Control Center page of the expanded panel (DESIGN.md "Control Center page"): battery chip and Focus icon in the
/// header, four tiles, two condensed sliders. Tiles and sliders open a detail view in place; nothing grows.
struct ControlsPage: View {
    let store: IslandStore
    @State private var detail: ControlDetail?

    private let cardColor = Color(hex: 0x1C1C1E)

    #if DEBUG
    /// `-IsletDebugDetail wifi|bluetooth|airdrop|mirroring|display|sound` opens a detail view straight away.
    private static let debugDetail: ControlDetail? = {
        switch UserDefaults.standard.string(forKey: "IsletDebugDetail") {
        case "wifi": .wifi
        case "bluetooth": .bluetooth
        case "airdrop": .airdrop
        case "mirroring": .mirroring
        case "display": .display
        case "sound": .sound
        default: nil
        }
    }()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let detail {
                ControlDetailView(store: store, detail: detail)
            } else {
                tiles
                sliders
            }
        }
        #if DEBUG
        .onAppear { if detail == nil { detail = Self.debugDetail } }
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if let detail {
                Button { self.detail = nil } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text(detail.title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    }.foregroundStyle(Color.isletSecondary).frame(height: 26)
                }.buttonStyle(.plain)
            } else {
                Text("CONTROLS").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary)
                if let power = store.power, power.state.hasBattery { batteryChip(power.state) }
                if let f = store.focus?.active { focusIcon(f) }
            }
            Spacer(minLength: 4)
            if let m = store.media, let monitor = store.mediaMonitor { MiniPlayer(media: m, monitor: monitor, store: store) }
            SettingsGear(store: store)
        }
        .frame(height: 26)
    }

    private func batteryChip(_ s: PowerMonitor.State) -> some View {
        HStack(spacing: 4) {
            Image(systemName: s.charging || s.onAC ? "bolt.fill" : "battery.75")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(s.charging ? Color.isletGreen : Color.isletSecondary)
            Text("\(s.percent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText)
        }
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(cardColor))
        .help(batteryHelp(s))
    }

    private func batteryHelp(_ s: PowerMonitor.State) -> String {
        s.charged ? "Fully charged" : s.charging ? "Charging" : s.onAC ? "Plugged in" : "On battery"
    }

    private func focusIcon(_ f: FocusMode) -> some View {
        Image(systemName: f.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xBF5AF2))
            .frame(width: 22, height: 22).background(Circle().fill(cardColor)).help(f.name)
    }

    // MARK: Tiles

    @ViewBuilder private var tiles: some View {
        HStack(spacing: 10) {
            if let wifi = store.wifi {
                ControlTile(icon: wifi.powerOn ? "wifi" : "wifi.slash", title: "Wi-Fi",
                            status: wifi.powerOn ? (wifi.ssid ?? "Not connected") : "Off",
                            on: wifi.powerOn, accent: Color(hex: 0x0A84FF),
                            toggle: { wifi.setPower(!wifi.powerOn) }, open: { detail = .wifi })
            }
            if let bt = store.bluetooth {
                let connected = bt.devices.filter(\.connected)
                ControlTile(icon: "bluetooth", symbol: false, title: "Bluetooth",
                            status: !bt.powerOn ? "Off" : (connected.count == 1 ? connected[0].name : (connected.isEmpty ? "On" : "\(connected.count) devices")),
                            on: bt.powerOn, accent: Color(hex: 0x0A84FF),
                            toggle: { bt.setPower(!bt.powerOn) }, open: { detail = .bluetooth })
            }
            if let ad = store.airdrop {
                ControlTile(icon: "dot.radiowaves.left.and.right", title: "AirDrop",
                            status: ad.mode == .contacts ? "Contacts" : ad.mode.rawValue,
                            on: ad.mode != .off, accent: Color(hex: 0x0A84FF),
                            toggle: { ad.toggle() }, open: { detail = .airdrop })
            }
            ControlTile(icon: "rectangle.on.rectangle", title: "Mirroring",
                        status: Self.mirroringStatus(), on: false, accent: Color(hex: 0x0A84FF),
                        toggle: { detail = .mirroring }, open: { detail = .mirroring })
        }
        .frame(height: 74)
    }

    private static func mirroringStatus() -> String {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return n > 1 ? "\(n) displays" : "Displays"
    }

    // MARK: Sliders

    @ViewBuilder private var sliders: some View {
        if let levels = store.levels {
            HStack(spacing: 10) {
                CondensedSlider(icon: "sun.max.fill", value: levels.brightness, enabled: levels.brightnessAvailable,
                                set: { levels.setBrightness($0) }, expand: { detail = .display })
                CondensedSlider(icon: levels.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: levels.muted ? 0 : levels.volume,
                                enabled: true, set: { levels.setVolume($0) }, expand: { detail = .sound })
            }
            .frame(height: 52)
        }
    }
}

enum ControlDetail {
    case display, sound, wifi, bluetooth, airdrop, mirroring
    var title: String {
        switch self {
        case .display: "Display"
        case .sound: "Sound"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .airdrop: "AirDrop"
        case .mirroring: "Screen Mirroring"
        }
    }
}

// MARK: - Tile

/// Control Center style: tap the round icon to switch it, tap the rest of the tile to open its details.
struct ControlTile: View {
    var icon: String
    var symbol = true
    var title: String
    var status: String
    var on: Bool
    var accent: Color
    var toggle: () -> Void
    var open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: toggle) {
                ZStack {
                    Circle().fill(on ? accent : Color(hex: 0x3A3A3C))
                    glyph.foregroundStyle(.white)
                }.frame(width: 28, height: 28)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                Text(status).font(.system(size: 11)).foregroundStyle(Color.isletSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1C1C1E)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: open)
    }

    @ViewBuilder private var glyph: some View {
        if icon == "bluetooth" { BluetoothGlyph().frame(width: 12, height: 17) }
        else { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
    }
}

/// SF Symbols has no Bluetooth rune; this draws it.
struct BluetoothGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var p = Path()
            p.move(to: CGPoint(x: 0.05 * w, y: 0.28 * h)); p.addLine(to: CGPoint(x: 0.95 * w, y: 0.72 * h))
            p.addLine(to: CGPoint(x: 0.5 * w, y: h)); p.addLine(to: CGPoint(x: 0.5 * w, y: 0))
            p.addLine(to: CGPoint(x: 0.95 * w, y: 0.28 * h)); p.addLine(to: CGPoint(x: 0.05 * w, y: 0.72 * h))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Sliders

/// A slider that adjusts while dragging and, when tapped without moving, asks for more room.
struct ValueSlider: View {
    var value: Double
    var height: CGFloat = 8
    var enabled = true
    var onChange: (Double) -> Void
    var onTap: (() -> Void)?
    @State private var dragged = false

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0x48484A))
                Capsule().fill(Color.white).frame(width: max(height, w * CGFloat(min(max(value, 0), 1))))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard enabled else { return }
                    if !dragged && abs(g.translation.width) < 3 { return }
                    dragged = true
                    onChange(Double(min(max(g.location.x / w, 0), 1)))
                }
                .onEnded { g in
                    if !dragged {
                        if let onTap { onTap() } else if enabled { onChange(Double(min(max(g.location.x / w, 0), 1))) }
                    }
                    dragged = false
                })
            .opacity(enabled ? 1 : 0.4)
        }
    }
}

struct CondensedSlider: View {
    var icon: String
    var value: Double
    var enabled: Bool
    var set: (Double) -> Void
    var expand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).frame(width: 20)
            ValueSlider(value: value, enabled: enabled, onChange: set, onTap: expand)
            Text("\(Int((value * 100).rounded()))%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Color.isletText).frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1C1C1E)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: expand)
    }
}
