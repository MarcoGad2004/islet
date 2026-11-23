import SwiftUI

/// The messages inbox in the panel (DESIGN.md "Messages inbox"), opened from the messages pill: chats with new
/// messages first, then the other recent ones. A row opens its conversation, which has a back button to here.
struct InboxView: View {
    let store: IslandStore
    let messages: MessagesStore

    var body: some View {
        VStack(spacing: 8) {
            header
            if messages.inbox.isEmpty {
                Text("No recent messages").font(.system(size: 12)).foregroundStyle(Color.isletTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(messages.inbox) { row($0) }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16))
        .animation(.easeOut(duration: 0.25), value: messages.inbox)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { store.closeInbox() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text("MESSAGES").font(.system(size: 11, weight: .semibold)).tracking(0.8)
                }.foregroundStyle(Color.isletSecondary).frame(height: 26)
            }
            .buttonStyle(.plain)
            if messages.unreadCount > 0 {
                Text("\(messages.unreadCount) unread").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x0A84FF))
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                store.collapse()
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Messages.app"))
            } label: {
                HStack(spacing: 5) {
                    Text("Open Messages").font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.isletText).padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(Color.isletRing))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 30)
    }

    private func row(_ c: MessagesStore.ChatSummary) -> some View {
        let new = c.unread > 0
        return Button { store.openChat(c.chatID, fromInbox: true) } label: {
            HStack(spacing: 10) {
                ChatAvatar(photo: messages.photo(forChat: c.chatID), initial: c.initial, chatID: c.chatID, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(c.title).font(.system(size: 13, weight: new ? .bold : .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(Self.when(c.date)).font(.system(size: 11)).foregroundStyle(new ? Color(hex: 0x0A84FF) : Color.isletTertiary)
                    }
                    Text(c.preview.isEmpty ? " " : c.preview).font(.system(size: 12))
                        .foregroundStyle(new ? Color.isletText : Color.isletSecondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if new {
                    Text("\(c.unread)").font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Color(hex: 0x0A84FF)))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(new ? Color.white.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "11:31 AM" today, "Yesterday", a weekday this week, else "12 Nov".
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}
