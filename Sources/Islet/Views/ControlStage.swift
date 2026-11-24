import CoreGraphics
import SwiftUI

enum ControlDetail {
    case display, sound, wifi, bluetooth, mirroring, battery
    var title: String {
        switch self {
        case .display: "Display"
        case .sound: "Sound"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .mirroring: "Screen Mirroring"
        case .battery: "Battery"
        }
    }
}

/// The expanded panel's whole interior as one stage. Every element (sliders, tiles, the media name and artwork, the
/// detail cards) is always present and has a rectangle for each page, so changing page moves it there with a spring,
/// the same spring family as the notch's own bubble, instead of swapping views. Inner content cross-fades.
struct ControlStage: View {
    let store: IslandStore
    /// Flush with a notification pill showing: the header row goes up past the pill into the band beside the camera.
    var headerLift: CGFloat = 0
    /// Opened from quick info: what doesn't glide in from it fades in (DESIGN.md "Quick info").
    @Environment(\.quickInfoRest) private var rest
    @Environment(\.quickInfoNamespace) private var ns

    private enum Mode: Equatable { case controls, display, sound, wifi, bluetooth, mirroring, battery, media }

    private var mode: Mode {
        if store.expandedPage == .media, store.media != nil { return .media }
        switch store.controlDetail {
        case .display?: return .display
        case .sound?: return .sound
        case .wifi?: return .wifi
        case .bluetooth?: return .bluetooth
        case .mirroring?: return .mirroring
        case .battery?: return .battery
        case nil: return .controls
        }
    }

    private let W: CGFloat = 468
    /// The panel is flush with the top and the header row sits beside the camera (DESIGN.md "Flush panel").
    private var flush: Bool { store.flushLift > 0 }
    /// Flush: the header's room left of the camera, from the stage's left edge (the panel's centre is at 234).
    private var leftBand: CGFloat { 234 - CGFloat(store.geometry?.width ?? 190) / 2 - 10 }
    /// The header row's top: 0, or up past the pill when flush.
    private var headerY: CGFloat { -headerLift }
    private var H: CGFloat { store.expandedBodyHeight - 32 }
    private let glide = Animation.spring(response: 0.46, dampingFraction: 0.72)
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
            mediaElements(mode).opacity(rest)
            if let power = store.power, power.state.hasBattery {
                BatteryPage(power: power).slot(below, visible: mode == .battery)
            }
            if Feature.shazam.isOn { shazamButton.slot(shazamSlot, visible: mode == .controls).opacity(rest * headerFade) }
            if flush { notchSettings } else { gear }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .animation(glide, value: mode)
        .onChange(of: mode) { old, now in
            if old == .wifi { store.wifi?.stopBrowsingHotspots() }
            if old == .battery { store.power?.watchDetails(false) }
            switch now {
            case .wifi: store.wifi?.refresh(); store.wifi?.browseHotspots(); Task { await store.wifi?.scan() }
            case .bluetooth: store.bluetooth?.refresh()
            case .display: store.display?.refresh(); store.levels?.refresh()
            case .sound: store.levels?.refresh()
            case .mirroring: store.sidecar?.refresh()
            case .battery: store.power?.refresh(); store.power?.watchDetails(true); PowerModeController.shared.refresh()
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
            case "battery": store.setControlDetail(.battery)
            default: break
            }
        }
        #endif
    }

    // MARK: Header

    private func header(_ mode: Mode) -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                if !flush {
                    Text("CONTROLS").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary)
                        .opacity(rest)
                }
                if let power = store.power, power.state.hasBattery { batteryChip(power.state) }
                if Feature.messages.isOn, let m = store.messages, m.unreadCount > 0 { messagesChip(m.unreadCount).opacity(rest) }
                if let u = store.updater, let tag = u.availableTag { updatePill(u, tag).opacity(rest) }
                if Feature.focus.isOn, let f = store.focus?.active { focusIcon(f).opacity(rest) }
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
        // The mini player starts at x 198 when music is playing; otherwise the header can run up to the gear. Flush,
        // the header has the room left of the camera.
        .frame(width: flush ? leftBand : store.media != nil ? 196 : W - 40, height: 26, alignment: .leading)
        .offset(y: headerY)
        .opacity(headerFade)
    }

    /// The header row's pieces, faded out while the pointer is behind the camera.
    private var headerFade: Double { store.settingsHover ? 0 : 1 }

    /// Right-hand end of the header row (owner's request, 2026-11-23): Shazam sits at the far right, or just left of
    /// the mini player's art when music is loaded, so the battery chip on the left keeps its room.
    private var shazamSlot: CGRect {
        let x: CGFloat = store.media == nil ? (flush ? W - 22 : W - 26 - 8 - 22) : (flush ? W - 26 - 8 - 22 - 8 - 22 : 376)
        return CGRect(x: x, y: 2 + headerY, width: 22, height: 22)
    }

    /// A new version is out: click to close the panel and update, the progress playing out in the notch. Next to
    /// the mini player there is only room for the icon.
    private func updatePill(_ u: Updater, _ tag: String) -> some View {
        let compact = store.media != nil || flush
        let version = Updater.plain(tag)
        return Button {
            store.collapse()
            u.install(tag)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 11, weight: .semibold))
                if !compact { Text("Update \(version)").font(.system(size: 11, weight: .semibold)).fixedSize() }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 0 : 8).frame(width: compact ? 22 : nil, height: 22)
            .background(Capsule().fill(Color(hex: 0x0A84FF)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Dynamic Peninsula \(version) is available. Click to update and restart.")
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func title(_ mode: Mode) -> String {
        switch mode {
        case .media: "Now Playing"
        case .display: "Display"
        case .sound: "Sound"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .mirroring: flush ? "Mirroring" : "Screen Mirroring"
        case .battery: "Battery"
        case .controls: "Controls"
        }
    }

    private func back(_ mode: Mode) {
        if mode == .media { store.showControlsPage() } else { store.setControlDetail(nil) }
    }

    /// The battery in the header. Click it for the battery page.
    private func batteryChip(_ s: PowerMonitor.State) -> some View {
        Button { store.setControlDetail(.battery) } label: {
        HStack(spacing: 4) {
            Image(systemName: s.charging || s.onAC ? "bolt.fill" : "battery.75")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(s.charging ? Color.isletGreen : Color.isletSecondary)
                .quickInfoPiece(.batteryIcon, ns)
            Text("\(s.percent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText)
                .quickInfoPiece(.batteryText, ns)
        }
        .padding(.horizontal, 8).frame(height: 22)
        .background(IsletCard(shape: Capsule()).opacity(rest))
        .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(s.charged ? "Fully charged" : s.charging ? "Charging" : s.onAC ? "Plugged in" : "On battery")
    }

    /// New messages: click for the inbox.
    private func messagesChip(_ n: Int) -> some View {
        Button { store.openInbox() } label: {
            HStack(spacing: 4) {
                Image(systemName: "message.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0x0A84FF))
                Text("\(n)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 8).frame(height: 22)
            .background(IsletCard(shape: Capsule()))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(n == 1 ? "1 chat with unread messages" : "\(n) chats with unread messages")
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    /// Names the song playing nearby: the panel closes and the notch listens (DESIGN.md "Shazam").
    private var shazamButton: some View {
        Button { store.startShazam() } label: {
            Image(systemName: "shazam.logo.fill").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShazamView.blue)
                .frame(width: 22, height: 22).background(IsletCard(shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Shazam: name the song playing nearby")
    }

    private func focusIcon(_ f: FocusMode) -> some View {
        Image(systemName: f.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(f.color)
            .frame(width: 22, height: 22).background(IsletCard(shape: Circle())).help(f.name)
    }

    private var gear: some View {
        SettingsGear(store: store).slot(CGRect(x: W - 26, y: headerY, width: 26, height: 26)).opacity(rest)
    }

    /// Flush, there's no gear: the camera's area is the Settings button (owner's request, 2026-11-23; the hot spot is
    /// in IslandView, exactly the notch). With the pointer there the header row fades and "Click to open | ⚙ Settings"
    /// fades in on each side of it.
    private var notchSettings: some View {
        let notch = CGFloat(store.geometry?.width ?? 190)
        let left = 234 - notch / 2
        return ZStack(alignment: .topLeading) {
            Text("Click to open").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.isletSecondary)
                .frame(width: left - 10, height: 26, alignment: .trailing)
                .offset(y: headerY)
            HStack(spacing: 5) {
                Image(systemName: "gearshape.fill").font(.system(size: 11, weight: .semibold))
                Text("Settings").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.isletText)
            .frame(height: 26)
            .offset(x: left + notch + 10, y: headerY)
        }
        .opacity(store.settingsHover ? 1 : 0)
        .allowsHitTesting(false)
        .opacity(rest)
    }

    // MARK: Controls, tiles and sliders

    @ViewBuilder private func controlsElements(_ mode: Mode) -> some View {
        let inControls = mode == .controls
        if let wifi = store.wifi {
            card(index: 0, active: mode == .wifi, mode: mode, detailHeight: 232) {
                TileFace(icon: !wifi.powerOn ? "wifi.slash" : wifi.hotspot ? "personalhotspot" : "wifi",
                         title: wifi.hotspot ? "Hotspot" : "Wi-Fi",
                         status: wifi.powerOn ? (wifi.ssid ?? "Not connected") : "Off", on: wifi.powerOn,
                         toggle: { wifi.setPower(!wifi.powerOn) }, open: { store.setControlDetail(.wifi) },
                         iconPiece: .wifiIcon, statusPiece: .wifiName)
            } detail: { WiFiContent(wifi: wifi).frame(width: W, height: 232, alignment: .topLeading) }
        }
        if let bt = store.bluetooth {
            let connected = bt.devices.filter(\.connected)
            card(index: 1, active: mode == .bluetooth, mode: mode, detailHeight: 232) {
                TileFace(icon: "bluetooth", title: "Bluetooth",
                         status: !bt.powerOn ? "Off" : (connected.count == 1 ? connected[0].name : (connected.isEmpty ? "On" : "\(connected.count) devices")),
                         on: bt.powerOn, toggle: { bt.setPower(!bt.powerOn) }, open: { store.setControlDetail(.bluetooth) },
                         iconPiece: QuickInfoView.showsBluetooth(store) ? .bluetoothIcon : nil,
                         statusPiece: QuickInfoView.showsBluetooth(store) ? .bluetoothName : nil)
            } detail: { BluetoothContent(bt: bt).frame(width: W, height: 232, alignment: .topLeading) }
        }
        if let ad = store.airdrop {
            TileFace(icon: "dot.radiowaves.left.and.right", title: "AirDrop", status: ad.mode.status, on: ad.mode != .off,
                     toggle: { ad.openAirDrop(); store.collapse() }, open: { ad.openAirDrop(); store.collapse() })
                .frame(width: tileW, height: 74, alignment: .topLeading)
                .background(IsletCard(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
                .slot(tile(2), visible: inControls)
                .opacity(rest)
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
                .opacity(rest)
            // Keyboard backlight: only on the Display page, under the screen's slider, when the Mac has one.
            SliderCard(icon: levels.keyboard == 0 ? "light.min" : "light.max", value: levels.keyboard, enabled: true, large: true,
                       iconAction: {}, set: { levels.setKeyboard($0) }, expand: {})
                .slot(CGRect(x: 0, y: 102, width: W, height: 56), visible: bright && levels.keyboardAvailable)
            let loud = mode == .sound
            SliderCard(icon: levels.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: levels.muted ? 0 : levels.volume,
                       enabled: true, large: loud,
                       iconAction: { if loud { levels.toggleMute() } else { store.setControlDetail(.sound) } },
                       set: { levels.setVolume($0) }, expand: { store.setControlDetail(.sound) })
                .slot(loud ? sliderBig : volumeSmall, visible: inControls || loud)
                .opacity(rest)
            SoundOutputList(levels: levels).slot(CGRect(x: 0, y: 102, width: W, height: max(H - 102, 60)), visible: loud)
        }
        if let d = store.display {
            let y: CGFloat = store.levels?.keyboardAvailable == true ? 168 : 102
            DisplayToggleRow(display: d).slot(CGRect(x: 0, y: y, width: W, height: 62), visible: mode == .display)
        }
    }

    /// A tile that becomes a full-width card: the card frame glides, the tile face and the detail content cross-fade.
    private func card<Face: View, Detail: View>(index: Int, active: Bool, mode: Mode, detailHeight: CGFloat,
                                                @ViewBuilder face: () -> Face, @ViewBuilder detail: () -> Detail) -> some View {
        let r = active ? below : tile(index)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack(alignment: .topLeading) {
            face().frame(width: tileW, height: 74, alignment: .topLeading)
                .opacity(mode == .controls ? 1 : 0).allowsHitTesting(mode == .controls)
            detail().opacity(active ? 1 : 0).allowsHitTesting(active)
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        // The fill is the card's own background, sized by the card's frame, and drawn afresh on each page change:
        // a fill that shrank back from the detail page sometimes stopped drawing, leaving the tile without its card.
        // Open, the page sits straight on the island: the tile's box fades away as it glides out, and back as it returns.
        .background(IsletCard(shape: shape).id(active).transition(.identity).opacity(active ? 0 : rest))
        // While pieces glide in from quick info they start outside the tile, so the clip opens up until they land.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous).inset(by: rest < 1 ? -600 : 0))
        .offset(x: r.minX, y: r.minY)
        .opacity(mode == .controls || active ? 1 : 0)
        .allowsHitTesting(mode == .controls || active)
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
                .offset(x: isMedia ? 0 : flush ? W - 26 - 8 - 22 : 198, y: isMedia ? 48 : 2 + headerY)
                .opacity(isMedia ? 1 : headerFade)
                .help(flush && !isMedia ? m.title : "")
                .onTapGesture { if isMedia { monitor.activatePlayer(); store.collapse() } else { store.showMediaPage() } }

            Text(m.title)
                .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                .foregroundStyle(isMedia ? Color.isletText : Color.isletSecondary)
                // In the header row it stops short of Shazam (at x 376).
                .frame(width: isMedia || !Feature.shazam.isOn ? 240 : 196, height: 22, alignment: .leading)
                .scaleEffect(isMedia ? 1 : 12.0 / 17, anchor: .topLeading)
                .offset(x: isMedia ? 94 : 228, y: isMedia ? 54 : 6 + headerY)
                // Flush, there's no room for the name beside the camera: hovering the art shows it.
                .opacity(flush && !isMedia ? 0 : 1)
                .allowsHitTesting(!(flush && !isMedia))
                .onTapGesture { if !isMedia { store.showMediaPage() } }

            Text(m.artist).font(.system(size: 14)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                .slot(CGRect(x: 94, y: 78, width: 240, height: 18), visible: isMedia)
            Text(m.album).font(.system(size: 12)).foregroundStyle(Color.isletTertiary).lineLimit(1)
                .slot(CGRect(x: 94, y: 98, width: 240, height: 16), visible: isMedia && !m.album.isEmpty)

            Button { monitor.togglePlayPause() } label: {
                Image(systemName: m.playing ? "pause.fill" : "play.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText)
                    .frame(width: 26, height: 22).background(IsletCard(shape: Capsule()))
            }.buttonStyle(.plain).slot(CGRect(x: flush ? W - 26 : 406, y: 2 + headerY, width: 26, height: 22), visible: !isMedia)
                .opacity(headerFade)

            HStack(spacing: 16) {
                transport("backward.fill", 17) { monitor.previous() }
                transport(m.playing ? "pause.fill" : "play.fill", 24) { monitor.togglePlayPause() }
                transport("forward.fill", 17) { monitor.next() }
            }.slot(CGRect(x: W - 118, y: 68, width: 118, height: 40), visible: isMedia)

            Scrubber(media: m) { monitor.seek(to: $0) }
                .slot(CGRect(x: 0, y: 148, width: W, height: 20), visible: isMedia)

            SourceIcon(bundleID: m.bundleID, size: 20, playing: m.playing)
                .slot(CGRect(x: flush ? W - 20 : W - 26 - 10 - 20, y: 3 + headerY, width: 20, height: 20), visible: isMedia)
                .opacity(headerFade)
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
    /// Opened from quick info, these glide in from it; the rest of the tile fades in.
    var iconPiece: QuickInfoPieceID? = nil
    var statusPiece: QuickInfoPieceID? = nil
    @Environment(\.quickInfoRest) private var rest
    @Environment(\.quickInfoNamespace) private var ns

    var body: some View {
        // Icon and text centred in the tile, both ways.
        VStack(alignment: .center, spacing: 5) {
            Button(action: toggle) {
                ZStack {
                    Circle().fill(on ? Color(hex: 0x0A84FF) : Color(hex: 0x3A3A3C))
                    glyph.foregroundStyle(.white)
                }.frame(width: 28, height: 28)
                .modifier(PieceOrRest(piece: iconPiece, ns: ns, rest: rest))
            }.buttonStyle(.plain)
            VStack(alignment: .center, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                    .opacity(rest)
                Text(status).font(.system(size: 11)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                    .modifier(PieceOrRest(piece: statusPiece, ns: ns, rest: rest))
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
        .background(IsletCard(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
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

/// A piece that glides in from quick info, or otherwise fades in with the rest of the panel.
private struct PieceOrRest: ViewModifier {
    let piece: QuickInfoPieceID?
    let ns: Namespace.ID?
    let rest: Double
    func body(content: Content) -> some View {
        if let piece { content.quickInfoPiece(piece, ns) } else { content.opacity(rest) }
    }
}
