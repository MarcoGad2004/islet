import SwiftUI

/// The expanded panel (500 x 216): the media page while something plays, otherwise Display and Sound.
struct ExpandedView: View {
    let store: IslandStore

    var body: some View {
        Group {
            switch store.expandedPage {
            case .media: MediaPage(store: store)
            case .displaySound: DisplaySoundPage(store: store)
            }
        }
        .padding(16)
        .frame(width: CGFloat(IslandLayout.expandedWidth), height: IslandLayout.expandedBodyHeight)
    }
}

// MARK: - Media

private struct MediaPage: View {
    let store: IslandStore

    var body: some View {
        if let m = store.media, let monitor = store.mediaMonitor {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NOW PLAYING").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary)
                    Spacer()
                    Button { store.collapse() } label: {
                        Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletSecondary)
                            .frame(width: 26, height: 20)
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 14) {
                    Button { monitor.activatePlayer(); store.collapse() } label: {
                        ArtworkView(image: m.artwork, size: 80, radius: 14, playing: m.playing)
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                        Text(m.artist).font(.system(size: 14)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                        if !m.album.isEmpty { Text(m.album).font(.system(size: 12)).foregroundStyle(Color.isletTertiary).lineLimit(1) }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 16) {
                        control("backward.fill", 17) { monitor.previous() }
                        control(m.playing ? "pause.fill" : "play.fill", 24) { monitor.togglePlayPause() }
                        control("forward.fill", 17) { monitor.next() }
                    }
                }
                Scrubber(media: m) { monitor.seek(to: $0) }
            }
        } else {
            Text("Nothing playing").foregroundStyle(Color.isletSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func control(_ name: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: size)).foregroundStyle(Color.isletText).frame(width: 30, height: 30) }
            .buttonStyle(.plain)
    }
}

private struct Scrubber: View {
    let media: MediaInfo
    var onSeek: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let pos = dragging ?? media.position(at: ctx.date)
            HStack(spacing: 8) {
                Text(format(pos)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.isletTertiary).frame(width: 38, alignment: .leading)
                GeometryReader { geo in
                    let f = media.duration > 0 ? pos / media.duration : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x3A3A3C)).frame(height: 4)
                        Capsule().fill(Color.isletText).frame(width: max(4, geo.size.width * f), height: 4)
                    }
                    .frame(height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in dragging = media.duration * min(max(v.location.x / geo.size.width, 0), 1) }
                        .onEnded { v in
                            onSeek(media.duration * min(max(v.location.x / geo.size.width, 0), 1))
                            dragging = nil
                        })
                }.frame(height: 16)
                Text(format(media.duration)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.isletTertiary).frame(width: 38, alignment: .trailing)
            }
        }
    }

    private func format(_ s: Double) -> String {
        let t = Int(max(s, 0)); return "\(t / 60):\(String(format: "%02d", t % 60))"
    }
}

// MARK: - Display and Sound

private struct DisplaySoundPage: View {
    let store: IslandStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DISPLAY AND SOUND").font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary)
                Spacer()
            }
            HStack(spacing: 10) {
                if let power = store.power, power.state.hasBattery { BatteryBlock(state: power.state) }
                if let levels = store.levels {
                    VStack(spacing: 10) {
                        card {
                            Image(systemName: "sun.max.fill").frame(width: 20)
                            Slider(value: Binding(get: { levels.brightness }, set: { levels.setBrightness($0) }), in: 0...1)
                                .disabled(!levels.brightnessAvailable)
                            Text("\(Int((levels.brightness * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                        card {
                            Image(systemName: levels.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 20)
                            Slider(value: Binding(get: { levels.volume }, set: { levels.setVolume($0) }), in: 0...1)
                            Menu {
                                ForEach(levels.devices) { d in
                                    Button(d.name) { levels.selectOutput(d) }
                                }
                            } label: {
                                Text(levels.outputName.isEmpty ? "Output" : levels.outputName).lineLimit(1).frame(width: 104, alignment: .trailing)
                            }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        }
                    }
                }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { content() }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.isletText)
            .tint(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1C1C1E)))
    }
}

private struct BatteryBlock: View {
    let state: PowerMonitor.State

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: state.charging || state.onAC ? "bolt.fill" : "battery.75")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(state.charging ? Color.isletGreen : Color.isletSecondary)
            Spacer(minLength: 0)
            Text("\(state.percent)%").font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText)
            Text(status).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletSecondary)
            Text(timeText).font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
        }
        .padding(12)
        .frame(width: 112)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1C1C1E)))
    }

    private var status: String { state.charged ? "Fully charged" : state.charging ? "Charging" : state.onAC ? "Plugged in" : "On battery" }
    private var timeText: String {
        func hm(_ m: Int) -> String { "\(m / 60):\(String(format: "%02d", m % 60))" }
        if state.charging, let m = state.minutesToFull { return "\(hm(m)) to full" }
        if !state.onAC, let m = state.minutesToEmpty { return "\(hm(m)) left" }
        return " "
    }
}
