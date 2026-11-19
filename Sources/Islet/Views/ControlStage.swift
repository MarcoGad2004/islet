import CoreGraphics
import SwiftUI

enum ControlDetail {
    case display, sound, wifi, bluetooth, mirroring
    var title: String {
        switch self {
        case .display: "Display"
        case .sound: "Sound"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .mirroring: "Screen Mirroring"
        }
    }
}

/// The expanded panel's whole interior as one stage. Every element (sliders, tiles, the media name and artwork, the
/// detail cards) is always present and has a rectangle for each page, so changing page moves it there with a spring,
/// the same spring family as the notch's own bubble, instead of swapping views. Inner content cross-fades.
struct ControlStage: View {
    let store: IslandStore

    private enum Mode: Equatable { case controls, display, sound, wifi, bluetooth, mirroring, media }

    private var mode: Mode {
        if store.expandedPage == .media, store.media != nil { return .media }
        switch store.controlDetail {
        case .display?: return .display
        case .sound?: return .sound
        case .wifi?: return .wifi
        case .bluetooth?: return .bluetooth
        case .mirroring?: return .mirroring
        case nil: return .controls
        }
    }

    private let W: CGFloat = 468
    private var H: CGFloat { store.expandedBodyHeight - 32 }
    private let glide = Animation.spring(response: 0.46, dampingFraction: 0.72)
    private let cardFill = Color(hex: 0x1C1C1E)
    private let tileW: CGFloat = 109.5

    private func tile(_ i: Int) -> CGRect { CGRect(x: CGFloat(i) * (109.5 + 10), y: 36, width: 109.5, height: 74) }
    private var below: CGRect { CGRect(x: 0, y: 36, width: W, height: H - 36) }
    private let brightSmall = CGRect(x: 0, y: 120, width: 229, height: 56)
    private let volumeSmall = CGRect(x: 239, y: 120, width: 229, height: 56)
    private let sliderBig = CGRect(x: 0, y: 36, width: 468, height: 56)

    var body: some View {
        let mode = self.mode
        ZStack(alignment: .topLeading) {
            header(mode)
            controlsElements(mode)
            mediaElements(mode)
            gear
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .animation(glide, value: mode)
        .onChange(of: mode) { _, now in
            switch now {
            case .wifi: store.wifi?.refresh(); Task { await store.wifi?.scan() }
            case .bluetooth: store.bluetooth?.refresh()
            case .display: store.display?.refresh()
            case .sound: store.levels?.refresh()
            case .mirroring: store.sidecar?.refresh()
            default: break
            }
        }
        #if DEBUG
        .onAppear {
            switch UserDefaults.standard.string(forKey: "IsletDebugDetail") {
            case "wifi": store.setControlDetail(.wifi)
            case "bluetooth": store.setControlDetail(.bluetooth)
            case "mirroring": store.setControlDetail(.mirroring)
            case "display": store.setControlDetail(.display)
            case "sound": store.setControlDetail(.sound)
            default: break
            }
        }
        #endif
    }

    // MARK: Header

    private func header(_ mode: Mode) -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 10) {
                Text("CONTROLS").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary)
                if let power = store.power, power.state.hasBattery { batteryChip(power.state) }
                if let f = store.focus?.active { focusIcon(f) }
            }
            .opacity(mode == .controls ? 1 : 0)
            .allowsHitTesting(mode == .controls)

            Button { back(mode) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text(title(mode).uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.8)
                        .contentTransition(.opacity)
                }.foregroundStyle(Color.isletSecondary).frame(height: 26)
            }
            .buttonStyle(.plain)
            .opacity(mode == .controls ? 0 : 1)
            .allowsHitTesting(mode != .controls)
        }
        .frame(width: 190, height: 26, alignment: .leading)
    }

    private func title(_ mode: Mode) -> String {
        switch mode {
        case .media: "Now Playing"
        case .display: "Display"
        case .sound: "Sound"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .mirroring: "Screen Mirroring"
        case .controls: "Controls"
        }
    }

    private func back(_ mode: Mode) {
        if mode == .media { store.showControlsPage() } else { store.setControlDetail(nil) }
    }

    private func batteryChip(_ s: PowerMonitor.State) -> some View {
        HStack(spacing: 4) {
            Image(systemName: s.charging || s.onAC ? "bolt.fill" : "battery.75")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(s.charging ? Color.isletGreen : Color.isletSecondary)
            Text("\(s.percent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText)
        }
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(cardFill))
        .help(s.charged ? "Fully charged" : s.charging ? "Charging" : s.onAC ? "Plugged in" : "On battery")
    }

    private func focusIcon(_ f: FocusMode) -> some View {
        Image(systemName: f.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xBF5AF2))
            .frame(width: 22, height: 22).background(Circle().fill(cardFill)).help(f.name)
    }

    private var gear: some View {
        SettingsGear(store: store).slot(CGRect(x: W - 26, y: 0, width: 26, height: 26))
    }

    // MARK: Controls, tiles and sliders

    @ViewBuilder private func controlsElements(_ mode: Mode) -> some View {
        let inControls = mode == .controls
        if let wifi = store.wifi {
            card(index: 0, active: mode == .wifi, mode: mode, detailHeight: 232) {
                TileFace(icon: wifi.powerOn ? "wifi" : "wifi.slash", title: "Wi-Fi",
                         status: wifi.powerOn ? (wifi.ssid ?? "Not connected") : "Off", on: wifi.powerOn,
                         toggle: { wifi.setPower(!wifi.powerOn) }, open: { store.setControlDetail(.wifi) })
            } detail: { WiFiContent(wifi: wifi).frame(width: W, height: 232, alignment: .topLeading) }
        }
        if let bt = store.bluetooth {
            let connected = bt.devices.filter(\.connected)
            card(index: 1, active: mode == .bluetooth, mode: mode, detailHeight: 232) {
                TileFace(icon: "bluetooth", title: "Bluetooth",
                         status: !bt.powerOn ? "Off" : (connected.count == 1 ? connected[0].name : (connected.isEmpty ? "On" : "\(connected.count) devices")),
                         on: bt.powerOn, toggle: { bt.setPower(!bt.powerOn) }, open: { store.setControlDetail(.bluetooth) })
            } detail: { BluetoothContent(bt: bt).frame(width: W, height: 232, alignment: .topLeading) }
        }
        if let ad = store.airdrop {
            TileFace(icon: "dot.radiowaves.left.and.right", title: "AirDrop", status: ad.mode.status, on: ad.mode != .off,
                     toggle: { ad.openAirDrop(); store.collapse() }, open: { ad.openAirDrop(); store.collapse() })
                .frame(width: tileW, height: 74, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardFill))
                .slot(tile(2), visible: inControls)
        }
        card(index: 3, active: mode == .mirroring, mode: mode, detailHeight: 148) {
            TileFace(icon: "rectangle.on.rectangle", title: "Mirroring", status: Self.mirroringStatus(store.sidecar), on: false,
                     toggle: { store.setControlDetail(.mirroring) }, open: { store.setControlDetail(.mirroring) })
        } detail: { MirroringContent(sidecar: store.sidecar).frame(width: W, height: 148, alignment: .topLeading) }

        if let levels = store.levels {
            let bright = mode == .display
            SliderCard(icon: "sun.max.fill", value: levels.brightness, enabled: levels.brightnessAvailable, large: bright,
                       iconAction: { if !bright { store.setControlDetail(.display) } },
                       set: { levels.setBrightness($0) }, expand: { store.setControlDetail(.display) })
                .slot(bright ? sliderBig : brightSmall, visible: inControls || bright)
            let loud = mode == .sound
            SliderCard(icon: levels.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: levels.muted ? 0 : levels.volume,
                       enabled: true, large: loud,
                       iconAction: { if loud { levels.toggleMute() } else { store.setControlDetail(.sound) } },
                       set: { levels.setVolume($0) }, expand: { store.setControlDetail(.sound) })
                .slot(loud ? sliderBig : volumeSmall, visible: inControls || loud)
            SoundOutputList(levels: levels).slot(CGRect(x: 0, y: 102, width: W, height: max(H - 102, 60)), visible: loud)
        }
        if let d = store.display {
            DisplayToggleRow(display: d).slot(CGRect(x: 0, y: 102, width: W, height: 62), visible: mode == .display)
        }
    }

    /// A tile that becomes a full-width card: the card frame glides, the tile face and the detail content cross-fade.
    private func card<Face: View, Detail: View>(index: Int, active: Bool, mode: Mode, detailHeight: CGFloat,
                                                @ViewBuilder face: () -> Face, @ViewBuilder detail: () -> Detail) -> some View {
        let r = active ? below : tile(index)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardFill)
            face().frame(width: tileW, height: 74, alignment: .topLeading)
                .opacity(mode == .controls ? 1 : 0).allowsHitTesting(mode == .controls)
            detail().opacity(active ? 1 : 0).allowsHitTesting(active)
        }
        .slot(r, visible: mode == .controls || active, clip: 14)
    }

    private static func mirroringStatus(_ sidecar: SidecarController?) -> String {
        if let s = sidecar, s.devices.contains(where: \.connected) { return "iPad" }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return n > 1 ? "\(n) displays" : "Displays"
    }

    // MARK: Media: the mini player in the header becomes the Now Playing page

    @ViewBuilder private func mediaElements(_ mode: Mode) -> some View {
        if let m = store.media, let monitor = store.mediaMonitor {
            let isMedia = mode == .media
            ArtworkView(image: m.artwork, size: 80, radius: 14, playing: m.playing)
                .frame(width: 80, height: 80, alignment: .topLeading)
                .scaleEffect(isMedia ? 1 : 22.0 / 80, anchor: .topLeading)
                .offset(x: isMedia ? 0 : 198, y: isMedia ? 48 : 2)
                .onTapGesture { if isMedia { monitor.activatePlayer(); store.collapse() } else { store.showMediaPage() } }

            Text(m.title)
                .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                .foregroundStyle(isMedia ? Color.isletText : Color.isletSecondary)
                .frame(width: 240, height: 22, alignment: .leading)
                .scaleEffect(isMedia ? 1 : 12.0 / 17, anchor: .topLeading)
                .offset(x: isMedia ? 94 : 228, y: isMedia ? 54 : 6)
                .onTapGesture { if !isMedia { store.showMediaPage() } }

            Text(m.artist).font(.system(size: 14)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                .slot(CGRect(x: 94, y: 78, width: 240, height: 18), visible: isMedia)
            Text(m.album).font(.system(size: 12)).foregroundStyle(Color.isletTertiary).lineLimit(1)
                .slot(CGRect(x: 94, y: 98, width: 240, height: 16), visible: isMedia && !m.album.isEmpty)

            Button { monitor.togglePlayPause() } label: {
                Image(systemName: m.playing ? "pause.fill" : "play.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText)
                    .frame(width: 26, height: 22).background(Capsule().fill(cardFill))
            }.buttonStyle(.plain).slot(CGRect(x: 406, y: 2, width: 26, height: 22), visible: !isMedia)

            HStack(spacing: 16) {
                transport("backward.fill", 17) { monitor.previous() }
                transport(m.playing ? "pause.fill" : "play.fill", 24) { monitor.togglePlayPause() }
                transport("forward.fill", 17) { monitor.next() }
            }.slot(CGRect(x: W - 118, y: 68, width: 118, height: 40), visible: isMedia)

            Scrubber(media: m) { monitor.seek(to: $0) }
                .slot(CGRect(x: 0, y: 148, width: W, height: 20), visible: isMedia)

            SourceIcon(bundleID: m.bundleID, size: 20, playing: m.playing)
                .slot(CGRect(x: W - 26 - 10 - 20, y: 3, width: 20, height: 20), visible: isMedia)
        }
    }

    private func transport(_ name: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: size)).foregroundStyle(Color.isletText).frame(width: 30, height: 30) }
            .buttonStyle(.plain)
    }
}

// MARK: - Placement

extension View {
    /// Gives the view a rectangle on the stage. Changing the rectangle (or visibility) animates with the stage's spring.
    func slot(_ r: CGRect, visible: Bool = true, clip: CGFloat = 0) -> some View {
        frame(width: r.width, height: r.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: clip, style: .continuous))
            .offset(x: r.minX, y: r.minY)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
    }
}

// MARK: - Tile face and slider card

/// Control Center style: tap the round icon to switch it, tap the rest of the tile to open its details.
struct TileFace: View {
    var icon: String
    var title: String
    var status: String
    var on: Bool
    var toggle: () -> Void
    var open: () -> Void

    var body: some View {
        // Icon and text centred in the tile, both ways.
        VStack(alignment: .center, spacing: 5) {
            Button(action: toggle) {
                ZStack {
                    Circle().fill(on ? Color(hex: 0x0A84FF) : Color(hex: 0x3A3A3C))
                    glyph.foregroundStyle(.white)
                }.frame(width: 28, height: 28)
            }.buttonStyle(.plain)
            VStack(alignment: .center, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                Text(status).font(.system(size: 11)).foregroundStyle(Color.isletSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    @ViewBuilder private var glyph: some View {
        if icon == "bluetooth" { BluetoothGlyph().frame(width: 12, height: 17) }
        else { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
    }
}

/// The brightness or volume slider: condensed on the controls page, large on its own page. One view, so it glides.
struct SliderCard: View {
    var icon: String
    var value: Double
    var enabled: Bool
    var large: Bool
    var iconAction: () -> Void
    var set: (Double) -> Void
    var expand: () -> Void

    var body: some View {
        HStack(spacing: large ? 12 : 10) {
            Button(action: iconAction) {
                Image(systemName: icon).font(.system(size: large ? 15 : 13, weight: .semibold)).frame(width: large ? 22 : 20)
            }.buttonStyle(.plain)
            ValueSlider(value: value, height: large ? 14 : 8, enabled: enabled, onChange: set, onTap: large ? nil : expand)
            RollingNumber(value: value, suffix: "%", size: large ? 13 : 12)
                .frame(width: large ? 42 : 38, alignment: .trailing)
        }
        .foregroundStyle(Color.isletText)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1C1C1E)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { if !large { expand() } }
    }
}

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
                    // Keys and outside changes glide; a drag follows the pointer directly.
                    .animation(dragged ? nil : .levelGlide, value: value)
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
