import SwiftUI

/// The expanded panel (500 x 216): the media page while something plays, otherwise Display and Sound.
struct ExpandedView: View {
    let store: IslandStore

    var body: some View {
        // Pages and details cross-fade while the shape bubbles to its new size (both start together).
        let key = "\(store.expandedPage)-\(String(describing: store.controlDetail))"
        ZStack(alignment: .top) {
            Group {
                switch store.expandedPage {
                case .media: MediaPage(store: store)
                case .displaySound: ControlsPage(store: store)
                }
            }
            .id(key)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.28), value: key)
        .padding(16)
        .frame(width: CGFloat(IslandLayout.expandedWidth), height: store.expandedBodyHeight, alignment: .top)
    }
}

// MARK: - Media

private struct MediaPage: View {
    let store: IslandStore

    var body: some View {
        if let m = store.media, let monitor = store.mediaMonitor {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // Same header as the Control Center details: back to the controls.
                    Button { store.showControlsPage() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                            Text("NOW PLAYING").font(.system(size: 11, weight: .semibold)).tracking(0.8)
                        }.foregroundStyle(Color.isletSecondary).frame(height: 26)
                    }.buttonStyle(.plain).help("Back to controls")
                    Spacer()
                    SettingsGear(store: store)
                }.frame(height: 26)
                Spacer(minLength: 6)
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
                Spacer(minLength: 6)
                Scrubber(media: m) { monitor.seek(to: $0) }
                    .padding(.bottom, 2)
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

/// Paused (or otherwise idle) media, collapsed into the panel's header so it can be resumed from the notch
/// without the media taking over the island.
struct MiniPlayer: View {
    let media: MediaInfo
    let monitor: MediaMonitor
    let store: IslandStore

    var body: some View {
        HStack(spacing: 8) {
            Button { store.showMediaPage() } label: {
                HStack(spacing: 8) {
                    ArtworkView(image: media.artwork, size: 22, radius: 6, playing: media.playing)
                    Text(media.artist.isEmpty ? media.title : "\(media.title) · \(media.artist)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletSecondary)
                        .lineLimit(1).frame(maxWidth: 170, alignment: .leading)
                }
            }.buttonStyle(.plain)
            Button { monitor.togglePlayPause() } label: {
                Image(systemName: media.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText)
                    .frame(width: 26, height: 22)
                    .background(Capsule().fill(Color(hex: 0x1C1C1E)))
            }.buttonStyle(.plain)
        }
    }
}


/// Opens Islet's settings from the expanded notch (the menu bar icon can be hidden).
struct SettingsGear: View {
    let store: IslandStore
    var body: some View {
        Button { store.collapse(); store.openSettings?() } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.isletSecondary).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain).help("Settings")
    }
}
