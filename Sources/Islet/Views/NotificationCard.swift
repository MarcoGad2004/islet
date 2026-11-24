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
                        .font(.system(size: 12)).foregroundStyle(Color.isletSecondary)
                        .lineLimit(NotificationText.cardLines).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(height: NotificationText.cardBody(item))
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

/// How tall a notification's text is once it wraps (DESIGN.md "Notifications": the island grows with the text, up to a
/// limit, so it needn't be hovered to be read).
@MainActor enum NotificationText {
    static let compactLines = 6
    static let cardLines = 10

    /// Height of "Title · message" (title semibold) wrapped to `width`, at most `lines` lines. One line when text is hidden.
    static func height(_ item: NotificationItem, size: CGFloat, width: CGFloat, lines: Int, withApp: Bool = false) -> CGFloat {
        let hide = UserDefaults.standard.bool(forKey: NotificationWatcher.hideTextKey)
        let font = NSFont.systemFont(ofSize: size)
        let one = ceil(font.ascender - font.descender + font.leading)
        guard !hide, !item.line.isEmpty else { return one }
        let text = NSMutableAttributedString()
        if withApp {
            text.append(NSAttributedString(string: "\(item.app) · \(item.line)", attributes: [.font: font]))
        } else {
            text.append(NSAttributedString(string: item.heading, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)]))
            text.append(NSAttributedString(string: " · \(item.line)", attributes: [.font: font]))
        }
        let fit = text.boundingRect(with: NSSize(width: max(width, 40), height: .greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        return min(ceil(fit) + 1, one * CGFloat(lines) + 1)
    }

    /// Extra height the wide bar's body needs beyond its one-line 26 pt, and the chin's beyond its 36 pt.
    static func barBody(_ item: NotificationItem, notchWidth nw: Double) -> CGFloat {
        let w = CGFloat(nw + IslandLayout.wingsExtra - 2 * IslandLayout.levelSideInset)
        return max(IslandLayout.levelBodyHeight, height(item, size: 12, width: w, lines: compactLines) + 14)
    }
    static func chinBody(_ item: NotificationItem, more: Bool) -> CGFloat {
        let w = CGFloat(IslandLayout.chinWidth) - 32 - 30 - (more ? 56 : 0)
        return max(CGFloat(IslandLayout.chinHeight), height(item, size: 13, width: w, lines: compactLines) + 18)
    }
    static func cardBody(_ item: NotificationItem) -> CGFloat {
        let w = CGFloat(IslandLayout.notificationWidth) - 32 - 34 - 12
        let one = height(item, size: 12, width: w, lines: 1, withApp: true)
        let all = height(item, size: 12, width: w, lines: cardLines, withApp: true)
        return CGFloat(IslandLayout.notificationHeight) + (all - one)
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
            Button { store.openConversation(item) } label: { pillLabel("View", primary: true) }.buttonStyle(.plain)
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

/// The expanded panel's list of everything that just came in (DESIGN.md "Notifications", "The list"). Clicking a row
/// opens it in place: the whole message and its buttons.
struct NotificationList: View {
    let store: IslandStore
    @AppStorage(NotificationWatcher.hideTextKey) private var hideText = false

    static let rowHeight: CGFloat = 52
    static let headerHeight: CGFloat = 32
    /// Padding top and bottom, the header, and the rows (at most 4 showing; then it scrolls), the open one taller.
    static func height(rows: Int, open: NotificationItem? = nil) -> CGFloat {
        let extra = open.map { openRowHeight($0) - rowHeight } ?? 0
        return 12 + headerHeight + 4 + CGFloat(min(max(rows, 1), 4)) * rowHeight + extra + 12
    }

    /// The message's width in an open row: the panel, less the list's and row's padding, the icon and the close button.
    static let openTextWidth: CGFloat = CGFloat(IslandLayout.expandedWidth) - 28 - 20 - 28 - 12 - 12 - 24
    static let openLines = 6
    static let buttonsHeight: CGFloat = 28

    /// An open row: the title line, the whole message (up to 6 lines), then its buttons.
    static func openRowHeight(_ item: NotificationItem) -> CGFloat {
        let hide = UserDefaults.standard.bool(forKey: NotificationWatcher.hideTextKey)
        var text: CGFloat = 0
        if !hide && !item.line.isEmpty {
            let font = NSFont.systemFont(ofSize: 12)
            let fit = (item.line as NSString).boundingRect(with: NSSize(width: openTextWidth, height: .greatestFiniteMagnitude),
                                                          options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                          attributes: [.font: font]).height
            let line = ceil(font.ascender - font.descender + font.leading)
            text = min(ceil(fit), line * CGFloat(openLines)) + 2
        }
        return 10 + max(28, 17 + text) + 10 + buttonsHeight + 10
    }

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
                        NotificationRow(store: store, item: item, hideText: hideText, open: store.openNotificationID == item.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeOut(duration: 0.22), value: store.notifications.map(\.id))
                .animation(.spring(response: 0.32, dampingFraction: 0.9), value: store.openNotificationID)
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
    }
}

private struct NotificationRow: View {
    let store: IslandStore
    let item: NotificationItem
    let hideText: Bool
    let open: Bool
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: open ? .top : .center, spacing: 12) {
                Button { store.toggleNotificationRow(item) } label: {
                    HStack(alignment: open ? .top : .center, spacing: 12) {
                        NotificationIcon(item: item, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                                Spacer(minLength: 4)
                                NotificationWhen(item: item, prefix: item.app)
                            }
                            if !hideText && !item.line.isEmpty {
                                Text(item.line).font(.system(size: 12)).foregroundStyle(Color.isletSecondary)
                                    .lineLimit(open ? NotificationList.openLines : 1)
                                    .fixedSize(horizontal: false, vertical: open)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { store.removeNotification(item, .closed) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.isletText)
                        .frame(width: 24, height: 24).background(Circle().fill(Color.isletRing))
                }
                .buttonStyle(.plain).accessibilityLabel("Close")
            }
            if open {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    NotificationActions(store: store, item: item, height: NotificationList.buttonsHeight)
                    if !store.canReply(item) {
                        // The last pill is the main action: Open, unless the banner has its own.
                        Button { store.openNotificationInApp(item) } label: {
                            let primary = item.actions.isEmpty
                            Text("Open").font(.system(size: 12, weight: .semibold)).foregroundStyle(primary ? Color.black : Color.isletText)
                                .padding(.horizontal, 14).frame(height: NotificationList.buttonsHeight)
                                .background(Capsule().fill(primary ? Color.isletText : Color.isletRing))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, open ? 10 : 0)
        .frame(height: open ? NotificationList.openRowHeight(item) : NotificationList.rowHeight, alignment: open ? .top : .center)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(open ? 0.08 : hover ? 0.06 : 0)))
        .onHover { hover = $0 }
    }
}

/// "**Title** · message" on one line, the message in grey and cut short at the end.
struct NotificationLine: View {
    let item: NotificationItem
    var size: CGFloat = 12
    /// Wraps to this many lines (the island grows to fit); 1 cuts it short.
    var lines = 1
    @AppStorage(NotificationWatcher.hideTextKey) private var hideText = false

    var body: some View {
        let line = hideText ? "" : item.line
        (Text(item.heading).font(.system(size: size, weight: .semibold)).foregroundColor(.isletText)
         + Text(line.isEmpty ? "" : " · \(line)").font(.system(size: size)).foregroundColor(.isletSecondary))
            .lineLimit(lines).truncationMode(.tail).fixedSize(horizontal: false, vertical: lines > 1)
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
