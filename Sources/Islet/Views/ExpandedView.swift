import SwiftUI

/// The expanded panel: one stage where every element has a place for each page, so switching pages glides the
/// sliders, names and cards to their new positions instead of swapping views (see ControlStage).
struct ExpandedView: View {
    let store: IslandStore

    var body: some View {
        if store.expandedPage == .messages, let c = store.messages?.open {
            ConversationView(store: store, conversation: c)
                .frame(width: CGFloat(IslandLayout.expandedWidth), height: store.expandedBodyHeight, alignment: .topLeading)
        } else if store.expandedPage == .notifications {
            NotificationList(store: store)
                .frame(width: CGFloat(IslandLayout.expandedWidth), height: store.expandedBodyHeight, alignment: .topLeading)
        } else {
            // Waiting notifications as a pill at the top; the page moves down under it (DESIGN.md "In the panel").
            VStack(spacing: 0) {
                if store.showsNotificationPill {
                    NotificationPill(store: store)
                        .padding(.horizontal, 16).padding(.top, 12)
                        .frame(height: IslandLayout.notificationPillHeight, alignment: .bottom)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if store.showsActivityCards {
                    // iPhone Live Activities, one card each (DESIGN.md "iPhone Live Activities", "In the panel").
                    VStack(spacing: LiveActivityCard.gap) {
                        ForEach(store.liveActivities) { LiveActivityCard(store: store, activity: $0) }
                    }
                    .padding(.horizontal, 16).padding(.top, LiveActivityCard.top)
                    .frame(height: store.activityCardsHeight, alignment: .top)
                    .transition(.opacity)
                }
                page.frame(width: CGFloat(IslandLayout.expandedWidth), height: store.pageBodyHeight, alignment: .topLeading)
            }
            .frame(width: CGFloat(IslandLayout.expandedWidth), height: store.expandedBodyHeight, alignment: .topLeading)
            .animation(.easeOut(duration: 0.25), value: store.showsNotificationPill)
        }
    }

    @ViewBuilder private var page: some View {
        if store.expandedPage == .call, store.call?.phase == .active {
            CallPage(store: store)
                .padding(EdgeInsets(top: 14, leading: 24, bottom: 22, trailing: 24))
        } else {
            ControlStage(store: store)
                .padding(16)
        }
    }
}

struct Scrubber: View {
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
