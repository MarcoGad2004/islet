import SwiftUI

/// The hovered notification under the notch (DESIGN.md "Notifications"): the 360 x 72 card, 36 pt taller when the banner
/// has its own buttons (Duo's Deny and Approve).
struct NotificationCard: View {
    let store: IslandStore
    let item: NotificationItem
    @AppStorage(NotificationWatcher.hideTextKey) private var hideText = false

    var body: some View {
        let nh = store.geometry?.height ?? 34
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                NotificationIcon(item: item, size: 34, count: store.notificationCount)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                        Spacer(minLength: 4)
                        NotificationWhen(item: item)
                    }
                    Text(hideText || item.line.isEmpty ? item.app : "\(item.app) · \(item.line)")
                        .font(.system(size: 12)).foregroundStyle(Color.isletSecondary).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(height: CGFloat(IslandLayout.notificationHeight))
            if store.notificationHasButtons(item) {
                HStack(spacing: 8) {
                    Spacer()
                    NotificationActions(store: store, item: item, height: 28)
                }
                .frame(height: IslandLayout.notificationActionsHeight - 8, alignment: .top)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: CGFloat(IslandLayout.notificationWidth))
        // Another one arriving fades across in place.
        .id(item.id)
        .transition(.opacity.animation(.easeOut(duration: 0.2)))
        .animation(.easeOut(duration: 0.2), value: item.id)
        .padding(.top, nh)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// "now", or "Time Sensitive" in orange.
struct NotificationWhen: View {
    let item: NotificationItem
    var prefix: String? = nil
    var body: some View {
        if item.timeSensitive {
            Text("Time Sensitive").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xFF9F0A)).lineLimit(1)
        } else {
            Text(prefix.map { "\($0) · now" } ?? "now").font(.system(size: 11)).foregroundStyle(Color.isletTertiary).lineLimit(1)
        }
    }
}

/// The banner's own buttons as pills, the last (the app's main action) white. More than two go under "Options".
struct NotificationActions: View {
    let store: IslandStore
    let item: NotificationItem
    var height: CGFloat = 28

    var body: some View {
        let reply = store.canReply(item)
        banner(primaryLast: !reply)
        if reply {
            // Islet's own: the conversation, in the notch.
            Button { store.openConversation(item) } label: { pillLabel("Reply", primary: true) }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private func banner(primaryLast: Bool) -> some View {
        if item.actions.count > 2 {
            Menu {
                ForEach(item.actions, id: \.self) { name in
                    Button(name) { store.removeNotification(item, .action(name)) }
                }
            } label: {
                pillLabel("Options", primary: false)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        } else {
            ForEach(Array(item.actions.enumerated()), id: \.offset) { i, name in
                Button { store.removeNotification(item, .action(name)) } label: {
                    pillLabel(name, primary: primaryLast && i == item.actions.count - 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pillLabel(_ label: String, primary: Bool) -> some View {
        Text(label).font(.system(size: height < 28 ? 11 : 12, weight: .semibold)).foregroundStyle(primary ? Color.black : Color.isletText)
            .lineLimit(1)
            .padding(.horizontal, height < 28 ? 10 : 14).frame(height: height)
            .background(Capsule().fill(primary ? Color.isletText : Color.isletRing))
            .contentShape(Capsule())
    }
}

/// The app's icon, with a count from the second notification on. iPhone notifications (the app usually isn't on the
/// Mac) get an iPhone glyph instead.
struct NotificationIcon: View {
    let item: NotificationItem
    var size: CGFloat = 34
    var count: Int = 1

    var body: some View {
        Group {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Color(hex: 0x3A3A3C))
                    .overlay(Image(systemName: item.fromIPhone ? "iphone" : "bell.fill")
                        .font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(Color.isletText))
                    .padding(size * 0.03)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if count > 1 {
                Text("\(count)").font(.system(size: 10, weight: .bold)).monospacedDigit().foregroundStyle(Color.isletText)
                    .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Color(hex: 0x3A3A3C)))
                    .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                    .offset(x: 6, y: 5)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: count)
            }
        }
    }
}

/// The expanded panel's list of everything that just came in (a two-finger swipe down).
struct NotificationList: View {
    let store: IslandStore
    @AppStorage(NotificationWatcher.hideTextKey) private var hideText = false

    static let rowHeight: CGFloat = 52
    static let headerHeight: CGFloat = 32
    /// Padding top and bottom, the header, and the rows (at most 4 showing; then it scrolls).
    static func height(rows: Int) -> CGFloat { 12 + headerHeight + 4 + CGFloat(min(max(rows, 1), 4)) * rowHeight + 12 }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Button { store.closeNotificationList() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.isletText)
                        .frame(width: 24, height: 24).background(Circle().fill(Color.isletRing))
                }
                .buttonStyle(.plain).help("Back")
                Text("JUST NOW · \(store.notificationCount)").font(.system(size: 11, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Color.isletTertiary).monospacedDigit()
                Spacer()
                Button { store.endAllNotifications(.closed) } label: {
                    Text("Clear all").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.isletText)
                        .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(Color.isletRing))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.headerHeight)
            PanelScrollView(indicators: false) {
                VStack(spacing: 0) {
                    ForEach(store.notifications) { item in
                        NotificationRow(store: store, item: item, hideText: hideText)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeOut(duration: 0.22), value: store.notifications.map(\.id))
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
    }
}

private struct NotificationRow: View {
    let store: IslandStore
    let item: NotificationItem
    let hideText: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if !(item.isMessages && store.openConversation(item)) { store.removeNotification(item, .shown) }
            } label: {
                HStack(spacing: 12) {
                    NotificationIcon(item: item, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                            Spacer(minLength: 4)
                            NotificationWhen(item: item, prefix: item.app)
                        }
                        if !hideText && !item.line.isEmpty {
                            Text(item.line).font(.system(size: 12)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            NotificationActions(store: store, item: item, height: 26)
            Button { store.removeNotification(item, .closed) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.isletText)
                    .frame(width: 24, height: 24).background(Circle().fill(Color.isletRing))
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(.horizontal, 10)
        .frame(height: NotificationList.rowHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hover ? 0.06 : 0)))
        .onHover { hover = $0 }
    }
}

/// "**Title** · message" on one line, the message in grey and cut short at the end.
struct NotificationLine: View {
    let item: NotificationItem
    var size: CGFloat = 12
    @AppStorage(NotificationWatcher.hideTextKey) private var hideText = false

    var body: some View {
        let line = hideText ? "" : item.line
        (Text(item.heading).font(.system(size: size, weight: .semibold)).foregroundColor(.isletText)
         + Text(line.isEmpty ? "" : " · \(line)").font(.system(size: size)).foregroundColor(.isletSecondary))
            .lineLimit(1).truncationMode(.tail)
    }
}

/// Waiting notifications at the top of the panel (DESIGN.md "Notifications", "In the panel"): the newest one, the count,
/// and a chevron. Click for the list.
struct NotificationPill: View {
    let store: IslandStore
    @AppStorage(NotificationWatcher.hideTextKey) private var hideText = false
    @State private var hover = false

    var body: some View {
        if let n = store.notifications.first {
            Button { store.openNotificationList() } label: {
                HStack(spacing: 8) {
                    NotificationIcon(item: n, size: 20)
                    (Text(n.heading).fontWeight(.semibold).foregroundStyle(Color.isletText)
                        + Text(hideText || n.line.isEmpty ? "" : " · \(n.line)").foregroundStyle(Color.isletSecondary))
                        .font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 6)
                    if store.notificationCount > 1 {
                        Text("\(store.notificationCount)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Color.isletText).padding(.horizontal, 6).frame(minWidth: 20, minHeight: 18)
                            .background(Capsule().fill(Color.isletRing))
                            .contentTransition(.numericText())
                    }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.isletTertiary)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(IsletCard(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(hover ? 0.05 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.2), value: store.notificationCount)
        }
    }
}
