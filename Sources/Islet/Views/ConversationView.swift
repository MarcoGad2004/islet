import SwiftUI

/// A Messages conversation in the panel (DESIGN.md "Messages"): header, the latest messages (newest at the bottom), and a
/// reply field that sends through Messages.
struct ConversationView: View {
    @Bindable var store: IslandStore
    let conversation: MessagesStore.Conversation
    @FocusState private var focused: Bool

    private var tint: Color { Self.tint(iMessage: conversation.iMessage) }
    private static func tint(iMessage: Bool) -> Color { iMessage ? Color(hex: 0x0A84FF) : .isletGreen }

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
            if store.conversationFromInbox {
                Button { store.closeInbox() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.isletText)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.isletRing))
                }
                .buttonStyle(.plain).help("Inbox")
            }
            ChatAvatar(photo: store.messages?.photo(forChat: conversation.chatID), initial: conversation.initial,
                       chatID: conversation.chatID, size: 32)
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
        return PanelScrollView(anchorBottom: true, indicators: false, scrollTo: list.last?.key) {
            VStack(spacing: 3) {
                ForEach(Array(list.enumerated()), id: \.element.key) { i, m in
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
                            // On its way to Messages: faded and a touch smaller, filling in once Messages has it.
                            .opacity(m.inFlight ? 0.55 : 1)
                            .scaleEffect(m.inFlight ? 0.97 : 1, anchor: .bottomTrailing)
                        if i == lastMine, let status = Self.statusText(m.status) {
                            Text(status)
                                .font(.system(size: 10)).foregroundStyle(m.status == .failed ? Color.isletRedText : Color.isletTertiary)
                                .padding(.horizontal, 4).padding(.top, 2)
                                .contentTransition(.opacity)
                                .id(status)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: m.mine ? .trailing : .leading)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    .id(m.key)
                }
            }
            .padding(.horizontal, 2).padding(.bottom, 2)
        }
    }

    @ViewBuilder private func bubble(_ m: MessagesStore.Message) -> some View {
        let fill = m.mine ? Self.tint(iMessage: m.iMessage) : Color.isletRing
        if m.attachment {
            // Photos and stickers show as themselves; anything else (or a file Messages hasn't downloaded) is a chip.
            let files = m.attachments.isEmpty ? [MessagesStore.Attachment(sticker: false)] : m.attachments
            ForEach(Array(files.enumerated()), id: \.offset) { _, a in
                AttachmentView(attachment: a, mine: m.mine, fill: fill)
            }
        }
        if !m.text.isEmpty {
            Text(m.text).font(.system(size: 13)).lineSpacing(2).foregroundStyle(m.mine ? .white : Color.isletText)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
                .overlay(alignment: m.mine ? .topLeading : .topTrailing) {
                    if !m.reactions.isEmpty { reactions(m) }
                }
                .overlay(alignment: m.mine ? .bottomLeading : .bottomTrailing) {
                    // Stickers placed on the message, overlapping its corner as in Messages.
                    HStack(spacing: -10) {
                        ForEach(Array(m.stickers.prefix(3).enumerated()), id: \.offset) { i, a in
                            AttachmentImage(path: a.path, maxSize: 40)
                                .rotationEffect(.degrees(i % 2 == 0 ? -8 : 7))
                        }
                    }
                    .offset(x: m.mine ? -14 : 14, y: 14)
                    .allowsHitTesting(false)
                }
                .padding(.bottom, m.stickers.isEmpty ? 0 : 14)
                .padding(.top, m.reactions.isEmpty ? 0 : 12)
                .frame(maxWidth: 300, alignment: m.mine ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .contextMenu { menu(m) }
        }
    }

    /// The tapbacks on a message, on its top corner like Messages: one of each, yours tinted.
    private func reactions(_ m: MessagesStore.Message) -> some View {
        var seen = Set<String>()
        let unique = m.reactions.filter { seen.insert($0.emoji).inserted }
        let mine = Set(m.reactions.filter(\.mine).map(\.emoji))
        return HStack(spacing: 1) {
            ForEach(unique, id: \.emoji) { r in
                Text(r.emoji).font(.system(size: 11))
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(mine.contains(r.emoji) ? tint : Color(hex: 0x3A3A3C)))
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(hex: 0x1C1C1E)))
        .offset(x: m.mine ? -10 : 10, y: -14)
        .help(m.reactions.count > unique.count ? "\(m.reactions.count) reactions" : "")
    }

    /// Right-click: the six tapbacks (yours ticked; choosing it again takes it off), any emoji in Messages, Copy.
    @ViewBuilder private func menu(_ m: MessagesStore.Message) -> some View {
        let mine = m.reactions.first(where: \.mine)
        if m.id > 0 {
            ForEach(Tapback.allCases) { t in
                Button { store.messages?.react(t, to: m) } label: {
                    if mine?.tapback == t { Label("\(t.emoji)  \(t.name)", systemImage: "checkmark") } else { Text("\(t.emoji)  \(t.name)") }
                }
            }
            Button("Other Emoji in Messages…") { store.messages?.react(nil, to: m) }
            Divider()
        }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(m.text, forType: .string)
        }
    }

    // MARK: Reply

    private var replyField: some View {
        let hasText = !store.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            Button { showEmoji() } label: {
                Image(systemName: "face.smiling").font(.system(size: 15)).foregroundStyle(Color.isletSecondary)
                    .frame(width: 30, height: 30).background(Circle().fill(Color.isletRing))
            }
            .buttonStyle(.plain).help("Emoji & Symbols (⌃⌘Space)").accessibilityLabel("Emoji")
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

    /// The system's Emoji & Symbols picker, into the reply field.
    private func showEmoji() {
        focused = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            store.showCharacterPalette()
        }
    }

    // MARK: Helpers

    /// "Sending…", "Sent", "Delivered", "Read 2:31 PM", "Read Yesterday", "Read Mon", "Read 12 Nov", "Not delivered".
    static func statusText(_ s: MessagesStore.Message.Status) -> String? {
        switch s {
        case .none: return nil
        case .sending: return "Sending…"
        case .sent: return "Sent"
        case .delivered: return "Delivered"
        case .failed: return "Not delivered"
        case .read(let d):
            let cal = Calendar.current
            if cal.isDateInToday(d) { return "Read \(d.formatted(date: .omitted, time: .shortened))" }
            if cal.isDateInYesterday(d) { return "Read Yesterday" }
            if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 {
                return "Read \(d.formatted(.dateTime.weekday(.abbreviated)))"
            }
            return "Read \(d.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }

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

/// A chat's picture: the person's photo from Contacts, else their initial on the chat's colour.
struct ChatAvatar: View {
    let photo: NSImage?
    let initial: String
    let chatID: Int64
    let size: CGFloat

    var body: some View {
        Group {
            if let photo {
                Image(nsImage: photo).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                ConversationView.color(for: chatID)
                    .overlay(Text(initial).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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

/// A file with a message: a sticker on its own (no bubble), a photo as a rounded thumbnail (click opens it), anything
/// else as a chip saying what it is.
private struct AttachmentView: View {
    let attachment: MessagesStore.Attachment
    let mine: Bool
    let fill: Color

    var body: some View {
        if attachment.isImage, let path = attachment.path, FileManager.default.fileExists(atPath: path) {
            if attachment.sticker {
                AttachmentImage(path: path, maxSize: 96)
            } else {
                AttachmentImage(path: path, maxSize: 200, corner: 14)
                    .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    .help("Open in Preview")
            }
        } else {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(attachment.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(mine ? .white : Color.isletSecondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill.opacity(mine ? 0.7 : 1)))
            .onTapGesture { if let p = attachment.path { NSWorkspace.shared.open(URL(fileURLWithPath: p)) } }
        }
    }

    private var icon: String {
        switch attachment.label {
        case "Video": "video.fill"
        case "Audio message": "waveform"
        case "Sticker": "face.smiling"
        case "Photo": "photo"
        default: "paperclip"
        }
    }
}

/// An image from Messages' attachments, scaled down off the main thread and kept for the next look.
struct AttachmentImage: View {
    let path: String?
    var maxSize: CGFloat
    var corner: CGFloat = 0
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                let size = Self.fit(image.size, maxSize)
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: max(corner, 8), style: .continuous).fill(Color.white.opacity(0.06))
                    .frame(width: maxSize * 0.6, height: maxSize * 0.6)
            }
        }
        .task(id: path) {
            guard let path else { return }
            if let cached = ThumbnailCache.shared.object(forKey: path as NSString) { image = cached; return }
            let px = maxSize * 2
            let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                let url = URL(fileURLWithPath: path) as CFURL
                guard let src = CGImageSourceCreateWithURL(url, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: px,
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
            }.value
            if let loaded { ThumbnailCache.shared.setObject(loaded, forKey: path as NSString) }
            image = loaded
        }
    }

    private static func fit(_ s: NSSize, _ m: CGFloat) -> CGSize {
        guard s.width > 0, s.height > 0 else { return CGSize(width: m, height: m) }
        let k = min(1, m / max(s.width, s.height))
        return CGSize(width: s.width * k, height: s.height * k)
    }
}

private enum ThumbnailCache {
    nonisolated(unsafe) static let shared: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 60
        return c
    }()
}

