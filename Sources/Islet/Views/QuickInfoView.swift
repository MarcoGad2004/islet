import SwiftUI

/// Quick info (DESIGN.md "Quick info"): hovering an idle notch shows the time and date, the battery, and what Wi-Fi
/// and Bluetooth are connected to. In the wide bar: the time over the date in the left wing, the percentage over the
/// battery in the right, Wi-Fi and Bluetooth centred together in the body. In the chin: the time, date and battery on
/// the first row, Wi-Fi and Bluetooth on the second. Opening the panel from here, the Wi-Fi, Bluetooth and battery
/// pieces glide to their tiles and the header chip (matched by `QuickInfoPiece`).
struct QuickInfoView: View {
    let store: IslandStore
    let bar: Bool

    @Environment(\.quickInfoNamespace) private var ns

    var body: some View {
        let nw = CGFloat(store.geometry?.width ?? 190)
        let nh = CGFloat(store.geometry?.height ?? 34)
        Group {
            if bar {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        clock(stacked: true).frame(width: 60)
                        Color.clear.frame(width: nw)
                        battery(stacked: true).frame(width: 60)
                    }
                    .frame(height: nh)
                    connections(room: nw + 120 - 40)
                        .frame(height: IslandLayout.levelBodyHeight)
                        .offset(y: -1)
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        clock(stacked: false)
                        Spacer(minLength: 8)
                        battery(stacked: false)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 24)
                    connections(room: CGFloat(IslandLayout.quickChinWidth) - 36)
                        .frame(height: 24)
                }
                .frame(width: CGFloat(IslandLayout.quickChinWidth))
                .padding(.top, nh + 6)
            }
        }
        .foregroundStyle(Color.isletText)
    }

    // MARK: Time and date

    @ViewBuilder private func clock(stacked: Bool) -> some View {
        TimelineView(.everyMinute) { ctx in
            let time = ctx.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
            let date = ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            if stacked {
                VStack(spacing: 0) {
                    Text(time).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Text(date).font(.system(size: 9.5)).foregroundStyle(Color.isletSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                HStack(spacing: 6) {
                    Text(time).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Text(date).font(.system(size: 12)).foregroundStyle(Color.isletSecondary)
                }
                .lineLimit(1)
            }
        }
    }

    // MARK: Battery

    @ViewBuilder private func battery(stacked: Bool) -> some View {
        if let s = store.power?.state, s.hasBattery {
            let percent = Text("\(s.percent)%").font(.system(size: stacked ? 11.5 : 12, weight: .semibold)).monospacedDigit()
                .quickInfoPiece(.batteryText, ns)
            let low = s.percent <= 20 && !s.charging && !s.onAC
            // Plugged in (charging or holding at a limit) it's green, so the white bolt shows against the fill.
            let glyph = BatteryGlyph(percent: s.percent, tint: s.charging || s.onAC ? Color.isletGreen : low ? Color(hex: 0xFF453A) : Color.isletText,
                                     bolt: s.charging || s.onAC)
                .frame(width: BatteryMetrics.width(height: stacked ? 13 : 12), height: stacked ? 13 : 12)
                .quickInfoPiece(.batteryIcon, ns)
            if stacked {
                VStack(spacing: 2) { percent; glyph }
            } else {
                HStack(spacing: 6) { glyph; percent }
            }
        }
    }

    // MARK: Wi-Fi and Bluetooth

    /// Both, centred together; Wi-Fi alone takes the row.
    private func connections(room: CGFloat) -> some View {
        HStack(spacing: 24) {
            if let w = store.wifi {
                HStack(spacing: 6) {
                    Image(systemName: !w.powerOn || w.ssid == nil ? "wifi.slash" : w.hotspot ? "personalhotspot" : "wifi")
                        .font(.system(size: 12, weight: .semibold))
                        .quickInfoPiece(.wifiIcon, ns)
                    Text(!w.powerOn ? "Wi-Fi Off" : w.ssid ?? "Not connected")
                        .font(.system(size: 12, weight: .semibold))
                        .quickInfoPiece(.wifiName, ns)
                }
                .lineLimit(1)
            }
            if let name = bluetoothName {
                HStack(spacing: 5) {
                    BluetoothGlyph().frame(width: 8, height: 12)
                        .quickInfoPiece(.bluetoothIcon, ns)
                    Text(name).font(.system(size: 12, weight: .semibold))
                        .quickInfoPiece(.bluetoothName, ns)
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: room)
    }

    /// The connected device; "2 devices" for more; nothing when none is connected.
    private var bluetoothName: String? {
        guard let bt = store.bluetooth, bt.powerOn else { return nil }
        let connected = bt.devices.filter(\.connected)
        if connected.isEmpty { return nil }
        return connected.count == 1 ? connected[0].name : "\(connected.count) devices"
    }

    /// Quick info shows this Bluetooth piece, so the panel's Bluetooth tile glides from it.
    static func showsBluetooth(_ store: IslandStore) -> Bool {
        guard let bt = store.bluetooth, bt.powerOn else { return false }
        return bt.devices.contains(where: \.connected)
    }
}

// MARK: - Gliding into the panel

/// The pieces quick info shares with the panel.
enum QuickInfoPieceID: String {
    case wifiIcon, wifiName, bluetoothIcon, bluetoothName, batteryIcon, batteryText
}

private struct QuickInfoNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct QuickInfoRestKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    /// Set by the island while quick info or a panel opened from it shows; the shared pieces glide between them.
    var quickInfoNamespace: Namespace.ID? {
        get { self[QuickInfoNamespaceKey.self] }
        set { self[QuickInfoNamespaceKey.self] = newValue }
    }

    /// The panel opened from quick info: the opacity of everything that doesn't glide in from it (0 → 1).
    var quickInfoRest: Double {
        get { self[QuickInfoRestKey.self] }
        set { self[QuickInfoRestKey.self] = newValue }
    }
}

extension View {
    /// Its place is matched with the same piece in quick info or the panel, so it moves between them as they swap.
    /// Icons match their frame too, so a glyph grows into its tile's round button; text only moves.
    /// The level's icon, bar and number, matched between the row under the unlock and the level on its own.
    @ViewBuilder func levelPiece(_ id: String, _ ns: Namespace.ID?) -> some View {
        if let ns { matchedGeometryEffect(id: "level." + id, in: ns, properties: .position, anchor: .center) } else { self }
    }

    @ViewBuilder func quickInfoPiece(_ id: QuickInfoPieceID, _ ns: Namespace.ID?) -> some View {
        let frame = id == .wifiIcon || id == .bluetoothIcon
        if let ns { matchedGeometryEffect(id: id.rawValue, in: ns, properties: frame ? .frame : .position, anchor: .center) } else { self }
    }
}
