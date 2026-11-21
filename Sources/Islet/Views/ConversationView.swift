import SwiftUI

/// A Messages conversation in the panel (DESIGN.md "Messages"): header, the latest messages (newest at the bottom), and a
/// reply field that sends through Messages.
struct ConversationView: View {
    @Bindable var store: IslandStore
    let conversation: MessagesStore.Conversation
    @FocusState private var focused: Bool

    private var tint: Color { conversation.iMessage ? Color(hex: 0x0A84FF) : .isletGreen }

    var body: some View {
        VStack(spacing: 8) {
            header
            messages
            if let error = store.messages?.sendError {
                Text(error).font(.system(size: 11)).foregroundStyle(Color.isletRedText).frame(maxWidth: .infinity, alignment: .leading)
            }
            replyField
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
        .onAppear {
            // The panel becomes key as it opens; give it a moment, then put the cursor in the reply field.
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(120)); focused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(Self.color(for: conversation.chatID)).frame(width: 32, height: 32)
                .overlay(Text(conversation.initial).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                Text(conversation.subtitle).font(.system(size: 11)).foregroundStyle(Color.isletTertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { openInMessages() } label: {
                HStack(spacing: 5) {
                    Text("Open in Messages").font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.isletText).padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(Color.isletRing))
            }
            .buttonStyle(.plain)
            Button { store.collapse() } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.isletText)
                    .frame(width: 28, height: 28).background(Circle().fill(Color.isletRing))
            }
            .buttonStyle(.plain).help("Collapse")
        }
        .frame(height: 36)
    }

    private func openInMessages() {
        store.collapse()
        // A one-to-one chat opens at that person ("sms:" goes to Messages); a group opens Messages.
        let parts = conversation.guid.components(separatedBy: ";")
        if !conversation.isGroup, let handle = parts.last, !handle.isEmpty,
           let url = URL(string: "sms:\(handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle)") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Messages.app"))
        }
    }

    // MARK: Messages

    private var messages: some View {
        let list = conversation.messages
        let lastMine = list.lastIndex(where: \.mine)
        return PanelScrollView(anchorBottom: true, indicators: false, scrollTo: list.last?.id) {
            VStack(spacing: 3) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                    let prev = i > 0 ? list[i - 1] : nil
                    VStack(alignment: m.mine ? .trailing : .leading, spacing: 1) {
                        if prev == nil || m.date.timeIntervalSince(prev!.date) > 3600 {
                            Text(Self.stamp(m.date)).font(.system(size: 10)).foregroundStyle(Color.isletTertiary)
                                .frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 3)
                        }
                        if let sender = m.sender, prev?.sender != sender || prev?.mine == true {
                            Text(sender).font(.system(size: 10)).foregroundStyle(Color.isletTertiary).padding(.horizontal, 12).padding(.top, 3)
                        }
                        bubble(m)
                        if i == lastMine, m.status != .none {
                            Text(m.status == .sending ? "Sending…" : m.status == .delivered ? "Delivered" : "Not delivered")
                                .font(.system(size: 10)).foregroundStyle(m.status == .failed ? Color.isletRedText : Color.isletTertiary)
                                .padding(.horizontal, 4).padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: m.mine ? .trailing : .leading)
                    .id(m.id)
                }
            }
            .padding(.horizontal, 2).padding(.bottom, 2)
        }
    }

    @ViewBuilder private func bubble(_ m: MessagesStore.Message) -> some View {
        let fill = m.mine ? tint : Color.isletRing
        if m.attachment {
            HStack(spacing: 5) {
                Image(systemName: "paperclip").font(.system(size: 11, weight: .semibold))
                Text("Attachment").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(m.mine ? .white : Color.isletSecondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill.opacity(m.mine ? 0.7 : 1)))
        }
        if !m.text.isEmpty {
            Text(m.text).font(.system(size: 13)).lineSpacing(2).foregroundStyle(m.mine ? .white : Color.isletText)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
                .frame(maxWidth: 300, alignment: m.mine ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Reply

    private var replyField: some View {
        let hasText = !store.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            TextField("", text: $store.messageDraft, prompt: Text(conversation.placeholder).foregroundStyle(Color.isletTertiary))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Color.isletText)
                .focused($focused)
                .onSubmit { store.sendMessage(); focused = true }
                .onExitCommand { store.collapse() }
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Color(hex: 0x1C1C1E)))
                .overlay(Capsule().stroke(focused ? Color(hex: 0x0A84FF) : Color(hex: 0x3A3A3C), lineWidth: 1))
            Button { store.sendMessage() } label: {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(Circle().fill(hasText ? tint : Color(hex: 0x3A3A3C)))
            }
            .buttonStyle(.plain).disabled(!hasText).accessibilityLabel("Send")
        }
    }

    // MARK: Helpers

    /// "Today 2:31 PM", "Yesterday 9:04 AM", "Mon 2:31 PM", "12 Nov 2:31 PM".
    static func stamp(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "Today \(time)" }
        if cal.isDateInYesterday(d) { return "Yesterday \(time)" }
        if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 {
            return "\(d.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
        return "\(d.formatted(.dateTime.day().month(.abbreviated))) \(time)"
    }

    /// One colour per conversation, from the same set Messages' initials use.
    static func color(for id: Int64) -> Color {
        let colors: [UInt32] = [0x5E5CE6, 0xFF9F0A, 0x64D2FF, 0xBF5AF2, 0xFF375F, 0x30D158, 0x0A84FF]
        return Color(hex: colors[Int(abs(id) % Int64(colors.count))])
    }
}

/// A scrolling list in the panel that tells the swipe handling where it is and whether it can still scroll each way
/// (DESIGN.md "Gestures", "Over a list"): a swipe up over it closes the panel only when the list can't go that way.
struct PanelScrollView<Content: View>: View {
    var anchorBottom = false
    var indicators = true
    /// Scrolled to whenever it changes (the newest message).
    var scrollTo: Int64? = nil
    /// Kept in view whenever it changes, scrolling as little as possible (search's selected row).
    var follow: String? = nil
    @ViewBuilder var content: Content
    @State private var id = UUID()

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: indicators) {
                    content.background(GeometryReader { inner in
                        Color.clear.preference(key: ContentFrameKey.self, value: inner.frame(in: .named(id)))
                    })
                }
                .coordinateSpace(name: id)
                .defaultScrollAnchor(anchorBottom ? .bottom : .top)
                .onPreferenceChange(ContentFrameKey.self) { f in
                    let frame = outer.frame(in: .global), height = outer.size.height
                    MainActor.assumeIsolated {
                        PanelScrollRegions.shared.set(id, .init(frame: frame, atTop: f.minY >= -1, atBottom: f.maxY <= height + 1))
                    }
                }
                .onChange(of: scrollTo) { _, target in
                    guard let target else { return }
                    withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(target, anchor: .bottom) }
                }
                .onChange(of: follow) { _, target in
                    guard let target else { return }
                    withAnimation(.easeOut(duration: 0.15)) { reader.scrollTo(target) }
                }
            }
        }
        .onDisappear { PanelScrollRegions.shared.set(id, nil) }
    }
}

/// Where the panel's lists are and whether each is at its top / bottom, for the swipe handling.
@MainActor
final class PanelScrollRegions {
    static let shared = PanelScrollRegions()
    struct Region: Equatable { var frame: CGRect; var atTop: Bool; var atBottom: Bool }
    private var regions: [UUID: Region] = [:]
    func set(_ id: UUID, _ r: Region?) { regions[id] = r }
    func region(at p: CGPoint) -> Region? { regions.values.first { $0.frame.contains(p) } }
}

private struct ContentFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
