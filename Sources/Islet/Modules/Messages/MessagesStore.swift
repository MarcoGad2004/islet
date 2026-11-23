import AppKit
import Contacts
import SQLite3

/// Messages conversations in the notch (DESIGN.md "Messages", RESEARCH.md Q32-Q38).
///
/// Reads Messages' history (`~/Library/Messages/chat.db`, read only; needs Full Disk Access), names people from
/// Contacts, and sends replies by asking Messages to (Apple Events), so Islet itself never goes on the network.
/// Messages' database is private and may change with macOS: everything here fails quietly to "open Messages instead".
@MainActor @Observable
final class MessagesStore {
    static let enabledKey = "messagesInNotch"

    struct Message: Identifiable, Equatable {
        enum Status: Equatable { case none, sending, delivered, read(Date), failed }
        let id: Int64
        /// Messages' own id, which reactions point at.
        var guid: String = ""
        var text: String
        var mine: Bool
        var date: Date
        /// Who sent it, in a group.
        var sender: String?
        var attachment: Bool
        var status: Status
        /// Tapbacks on it, oldest first.
        var reactions: [Reaction] = []
        /// What came with it: photos, stickers, files.
        var attachments: [Attachment] = []
        /// Stickers someone placed on it.
        var stickers: [Attachment] = []
    }

    /// A file sent with a message, from Messages' attachments folder (readable with Full Disk Access).
    struct Attachment: Equatable, Hashable {
        var path: String?
        var mime: String?
        var uti: String?
        var name: String?
        var sticker: Bool

        var isImage: Bool {
            if mime?.hasPrefix("image/") == true { return true }
            guard let uti else { return false }
            return ["public.heic", "public.png", "public.jpeg", "com.compuserve.gif", "public.heif", "org.webmproject.webp"].contains(uti)
                || uti.hasPrefix("public.image")
        }

        /// What to call it when it can't be shown.
        var label: String {
            if sticker { return "Sticker" }
            if mime?.hasPrefix("video/") == true { return "Video" }
            if mime?.hasPrefix("audio/") == true || uti == "com.apple.coreaudio-format" { return "Audio message" }
            if isImage { return "Photo" }
            return name ?? "Attachment"
        }
    }

    struct Reaction: Equatable {
        var emoji: String
        var mine: Bool
        /// The tapback, when it's one of the six (not any emoji).
        var tapback: Tapback?
    }

    struct Conversation: Equatable {
        let chatID: Int64
        /// What Messages calls it in Apple Events (`chat id "…"`), e.g. "iMessage;-;+15551234567".
        var guid: String
        var title: String
        var isGroup: Bool
        var people: Int
        /// iMessage, or SMS / RCS (green bubbles).
        var iMessage: Bool
        var messages: [Message]

        var subtitle: String {
            let service = iMessage ? "iMessage" : "Text Message"
            return isGroup ? "\(people) people · \(service)" : service
        }
        var placeholder: String { iMessage ? "iMessage" : "Text Message" }
        var initial: String { String(title.first(where: { $0.isLetter || $0.isNumber }) ?? "#") }
    }

    private(set) var open: Conversation?

    /// A chat in the inbox: who, the latest message, and how many are new (DESIGN.md "Messages inbox").
    struct ChatSummary: Identifiable, Equatable {
        let chatID: Int64
        var title: String
        var preview: String
        var date: Date
        /// Incoming messages Messages hasn't marked read and the island hasn't shown yet.
        var unread: Int
        var id: Int64 { chatID }
        var initial: String { String(title.first(where: { $0.isLetter || $0.isNumber }) ?? "#") }
    }

    /// Chats with something new first, then the other recent ones.
    private(set) var inbox: [ChatSummary] = []
    /// New messages across all chats: the panel's messages pill shows when there are any.
    private(set) var unreadCount = 0
    @ObservationIgnored private var inboxWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var inboxTask: Task<Void, Never>?
    static let seenKey = "messagesSeenUntil"
    /// A reply that went out but hasn't shown up in the history yet: shown at once, "Sending…".
    private(set) var pending: [Message] = []
    /// The send itself failed (no permission, Messages refused).
    private(set) var sendError: String?
    /// A tapback is on its way (Messages is in front for a moment).
    private(set) var reacting = false

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var names: ContactNames?
    /// Whether `message` has `associated_message_emoji` (any-emoji tapbacks, macOS 15 and later).
    @ObservationIgnored private lazy var hasEmojiColumn: Bool =
        rows("pragma table_info(message)").contains { ($0[1] as? String) == "associated_message_emoji" }
    /// Whether `attachment` has `is_sticker` (macOS 11 and later).
    @ObservationIgnored private lazy var hasStickerColumn: Bool =
        rows("pragma table_info(attachment)").contains { ($0[1] as? String) == "is_sticker" }

    private static var dbPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db").path
    }

    /// Opens the database on first use. False without Full Disk Access.
    private func connect() -> Bool {
        if db != nil { return true }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(Self.dbPath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return false
        }
        db = handle
        return true
    }

    var available: Bool { enabled && connect() }

    // MARK: Finding the conversation of a notification

    /// The chat a Messages notification came from: the newest incoming message (in the last 10 minutes) whose text
    /// matches the notification's, else the newest incoming one.
    func chatID(for item: NotificationItem) -> Int64? {
        guard available else { return nil }
        let since = Self.dbDate(Date().addingTimeInterval(-600))
        let recent = rows("""
            select j.chat_id, m.text, m.attributedBody from message m join chat_message_join j on j.message_id = m.ROWID
            where m.is_from_me = 0 and m.date > ? and m.associated_message_type = 0 order by m.date desc limit 30
            """, [since])
        let wanted = Self.clean(item.body)
        for r in recent {
            let text = Self.clean(Self.text(r[1] as? String, r[2] as? Data) ?? "")
            if !wanted.isEmpty, !text.isEmpty, text == wanted || text.hasPrefix(wanted) || wanted.hasPrefix(text) { return r[0] as? Int64 }
        }
        return recent.first?[0] as? Int64
    }

    /// The one-to-one chat with someone, by any of their numbers or emails (search's Message). The newest such chat when
    /// there are several (iMessage and SMS). Numbers compare by their last 10 digits, like contact names.
    func chatID(forHandles handles: [String]) -> Int64? {
        guard available, !handles.isEmpty else { return nil }
        func key(_ h: String) -> String { h.contains("@") ? h.lowercased() : String(h.filter(\.isNumber).suffix(10)) }
        let wanted = Set(handles.map(key).filter { !$0.isEmpty })
        let sql = "select c.ROWID, h.id from chat c join chat_handle_join j on j.chat_id = c.ROWID join handle h on h.ROWID = j.handle_id "
            + "where (select count(*) from chat_handle_join x where x.chat_id = c.ROWID) = 1 order by c.ROWID desc"
        return rows(sql).first { ($0[1] as? String).map { wanted.contains(key($0)) } ?? false }?[0] as? Int64
    }

    #if DEBUG
    /// The chat of the latest message with exactly this text (the preview opens the one with "Islet test").
    func chatID(withText text: String) -> Int64? {
        guard available else { return nil }
        return rows("select j.chat_id, m.text from message m join chat_message_join j on j.message_id = m.ROWID where m.is_from_me = 1 order by m.date desc limit 200")
            .first { ($0[1] as? String) == text }?[0] as? Int64
    }

    /// The chat with the newest message, when there's no "Islet test".
    func latestChatID() -> Int64? {
        guard available else { return nil }
        return rows("select j.chat_id from message m join chat_message_join j on j.message_id = m.ROWID order by m.date desc limit 1").first?[0] as? Int64
    }
    #endif

    // MARK: The inbox

    /// Keeps the unread count (and the inbox) current as messages arrive, from Messages' write-ahead log.
    func startInbox() {
        guard enabled else { return }
        refreshInbox()
        watchInbox()
    }

    private func watchInbox() {
        inboxWatcher?.cancel()
        let fd = Darwin.open(Self.dbPath + "-wal", O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if src.data.contains(.delete) || src.data.contains(.rename) { self.watchInbox() }
                self.inboxTask?.cancel()
                self.inboxTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self?.refreshInbox()
                }
            }
        }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        inboxWatcher = src
    }

    /// Re-reads the unread messages and the recent chats.
    func refreshInbox() {
        guard available else { inbox = []; unreadCount = 0; return }
        names = names ?? ContactNames()
        names?.load()
        let seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Double] ?? [:]
        var unread: [Int64: Int] = [:]
        for r in rows("""
            select j.chat_id, m.date from message m join chat_message_join j on j.message_id = m.ROWID
            where m.is_from_me = 0 and m.is_read = 0 and m.associated_message_type = 0 and m.item_type = 0 and m.date > ?
            """, [Self.dbDate(Date().addingTimeInterval(-14 * 86400))]) {
            guard let chat = r[0] as? Int64, let d = r[1] as? Int64 else { continue }
            if let until = seen[String(chat)], Self.date(d).timeIntervalSinceReferenceDate <= until { continue }
            unread[chat, default: 0] += 1
        }
        let recent = rows("""
            select j.chat_id, max(m.date) from message m join chat_message_join j on j.message_id = m.ROWID
            where m.associated_message_type = 0 and m.date > ? group by j.chat_id order by max(m.date) desc limit 12
            """, [Self.dbDate(Date().addingTimeInterval(-30 * 86400))])
        var list: [ChatSummary] = recent.compactMap { r in
            guard let chat = r[0] as? Int64 else { return nil }
            return summary(chat, unread: unread[chat] ?? 0)
        }
        // An unread chat older than the recent ones still makes the list.
        for (chat, n) in unread where !list.contains(where: { $0.chatID == chat }) {
            if let s = summary(chat, unread: n) { list.append(s) }
        }
        list.sort { ($0.unread > 0) != ($1.unread > 0) ? $0.unread > 0 : $0.date > $1.date }
        if list != inbox { inbox = list }
        let total = unread.values.reduce(0, +)
        if total != unreadCount { unreadCount = total }
    }

    private func summary(_ chat: Int64, unread: Int) -> ChatSummary? {
        guard let title = title(of: chat) else { return nil }
        guard let r = rows("""
            select m.text, m.attributedBody, m.is_from_me, m.cache_has_attachments, m.date
            from message m join chat_message_join j on j.message_id = m.ROWID
            where j.chat_id = ? and m.associated_message_type = 0 order by m.date desc limit 1
            """, [chat]).first else { return nil }
        var text = (Self.text(r[0] as? String, r[1] as? Data) ?? "").replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = (r[3] as? Int64) == 1 ? "Attachment" : "" }
        if (r[2] as? Int64) == 1, !text.isEmpty { text = "You: " + text }
        return ChatSummary(chatID: chat, title: title.title, preview: text, date: Self.date(r[4] as? Int64 ?? 0), unread: unread)
    }

    /// A chat's name: its own, or the people in it.
    private func title(of chat: Int64) -> (title: String, isGroup: Bool)? {
        guard let c = rows("select display_name, style from chat where ROWID = ?", [chat]).first else { return nil }
        let handles = rows("select h.id from handle h join chat_handle_join j on j.handle_id = h.ROWID where j.chat_id = ?", [chat])
            .compactMap { $0[0] as? String }
        let display = (c[0] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (display ?? (handles.isEmpty ? "Messages" : handles.map { name(for: $0) }.joined(separator: ", ")), (c[1] as? Int64) == 43)
    }

    /// Shown in the island: what's there now no longer counts as new, even though Messages still has it unread (the
    /// island can only read Messages' history, not mark it).
    func markSeen(_ chat: Int64) {
        var seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Double] ?? [:]
        seen[String(chat)] = Date().timeIntervalSinceReferenceDate
        // Only chats from the last couple of weeks matter.
        if seen.count > 200 { seen = seen.filter { Date().timeIntervalSinceReferenceDate - $0.value < 30 * 86400 } }
        UserDefaults.standard.set(seen, forKey: Self.seenKey)
        refreshInbox()
    }

    // MARK: The open conversation

    func openChat(_ chatID: Int64) {
        guard available else { return }
        names = names ?? ContactNames()
        names?.load()
        pending = []
        sendError = nil
        open = load(chatID)
        watch()
    }

    func close() {
        watcher?.cancel(); watcher = nil
        reloadTask?.cancel()
        open = nil
        pending = []
        sendError = nil
    }

    func isOpen(_ chatID: Int64?) -> Bool { chatID != nil && open?.chatID == chatID }

    private func load(_ chatID: Int64) -> Conversation? {
        guard let c = rows("select guid, display_name, style, service_name from chat where ROWID = ?", [chatID]).first,
              let guid = c[0] as? String else { return nil }
        let handles = rows("select h.id from handle h join chat_handle_join j on j.handle_id = h.ROWID where j.chat_id = ?", [chatID])
            .compactMap { $0[0] as? String }
        let isGroup = (c[2] as? Int64) == 43
        let service = (c[3] as? String) ?? "iMessage"
        let display = (c[1] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title = display ?? (handles.isEmpty ? "Messages" : handles.map { name(for: $0) }.joined(separator: ", "))
        let raw = rows("""
            select m.ROWID, m.text, m.attributedBody, m.is_from_me, m.date, m.cache_has_attachments, m.is_delivered, m.error, h.id,
                   m.guid, m.date_read
            from message m join chat_message_join j on j.message_id = m.ROWID left join handle h on h.ROWID = m.handle_id
            where j.chat_id = ? and m.associated_message_type = 0 order by m.date desc limit 50
            """, [chatID])
        var messages: [Message] = raw.reversed().compactMap { r in
            guard let id = r[0] as? Int64 else { return nil }
            let mine = (r[3] as? Int64) == 1
            let attachment = (r[5] as? Int64) == 1
            var text = Self.text(r[1] as? String, r[2] as? Data) ?? ""
            text = text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && !attachment { return nil }
            let read = r[10] as? Int64 ?? 0
            let status: Message.Status = !mine ? .none
                : (r[7] as? Int64 ?? 0) != 0 ? .failed
                : read > 0 ? .read(Self.date(read))
                : (r[6] as? Int64) == 1 ? .delivered : .sending
            return Message(id: id, guid: r[9] as? String ?? "", text: text, mine: mine, date: Self.date(r[4] as? Int64 ?? 0),
                           sender: isGroup && !mine ? (r[8] as? String).map { name(for: $0) } : nil,
                           attachment: attachment, status: status)
        }
        addReactions(to: &messages, chatID: chatID)
        addAttachments(to: &messages, chatID: chatID)
        // A reply sent from the notch that the history now has replaces its "Sending…" copy.
        pending.removeAll { p in messages.contains { $0.mine && $0.text == p.text && $0.date >= p.date.addingTimeInterval(-5) } }
        messages += pending
        return Conversation(chatID: chatID, guid: guid, title: title, isGroup: isGroup, people: handles.count + 1,
                            iMessage: service == "iMessage", messages: messages)
    }

    /// Tapbacks on the loaded messages. Each person has one at a time on a message: the newest add (2000-2006) or
    /// removal (3000-3006) wins. `associated_message_guid` is "p:0/<guid>" (a part of the message) or "bp:<guid>".
    private func addReactions(to messages: inout [Message], chatID: Int64) {
        guard let oldest = messages.first?.date else { return }
        let emoji = hasEmojiColumn ? "m.associated_message_emoji" : "null"
        let raw = rows("""
            select m.associated_message_guid, m.associated_message_type, m.is_from_me, m.handle_id, \(emoji)
            from message m join chat_message_join j on j.message_id = m.ROWID
            where j.chat_id = ? and m.date >= ? and m.associated_message_type between 2000 and 3006 order by m.date
            """, [chatID, Self.dbDate(oldest)])
        var latest: [String: [String: Reaction?]] = [:] // message guid → person → reaction
        var order: [String: [String]] = [:]
        for r in raw {
            guard let target = r[0] as? String, let type = r[1] as? Int64 else { continue }
            let guid = target.components(separatedBy: "/").last.map { $0.hasPrefix("bp:") ? String($0.dropFirst(3)) : $0 } ?? target
            let mine = (r[2] as? Int64) == 1
            let person = mine ? "me" : "\(r[3] as? Int64 ?? 0)"
            var reaction: Reaction?
            if type < 3000 {
                let tapback = Tapback(rawValue: Int(type))
                guard let e = tapback?.emoji ?? (r[4] as? String) else { continue }
                reaction = Reaction(emoji: e, mine: mine, tapback: tapback)
            }
            if latest[guid]?[person] == nil { order[guid, default: []].append(person) }
            latest[guid, default: [:]][person] = .some(reaction)
        }
        for i in messages.indices {
            let g = messages[i].guid
            guard let people = order[g] else { continue }
            messages[i].reactions = people.compactMap { latest[g]?[$0] ?? nil }
        }
    }

    /// The files with the loaded messages, and stickers placed on them (`associated_message_type` 1000, pointing at
    /// the message like a tapback does).
    private func addAttachments(to messages: inout [Message], chatID: Int64) {
        let ids = messages.filter { $0.attachment && $0.id > 0 }.map(\.id)
        let sticker = hasStickerColumn ? "a.is_sticker" : "0"
        if !ids.isEmpty {
            let list = ids.map(String.init).joined(separator: ",") // integers only
            var found: [Int64: [Attachment]] = [:]
            for r in rows("""
                select j.message_id, a.filename, a.mime_type, a.uti, a.transfer_name, \(sticker)
                from message_attachment_join j join attachment a on a.ROWID = j.attachment_id
                where j.message_id in (\(list)) order by a.ROWID
                """) {
                guard let id = r[0] as? Int64 else { continue }
                found[id, default: []].append(Self.attachment(r, from: 1))
            }
            for i in messages.indices { messages[i].attachments = found[messages[i].id] ?? [] }
        }
        guard let oldest = messages.first?.date else { return }
        var placed: [String: [Attachment]] = [:]
        for r in rows("""
            select m.associated_message_guid, a.filename, a.mime_type, a.uti, a.transfer_name, 1
            from message m join chat_message_join cj on cj.message_id = m.ROWID
            join message_attachment_join j on j.message_id = m.ROWID join attachment a on a.ROWID = j.attachment_id
            where cj.chat_id = ? and m.date >= ? and m.associated_message_type = 1000 order by m.date
            """, [chatID, Self.dbDate(oldest)]) {
            guard let target = r[0] as? String else { continue }
            let guid = target.components(separatedBy: "/").last.map { $0.hasPrefix("bp:") ? String($0.dropFirst(3)) : $0 } ?? target
            placed[guid, default: []].append(Self.attachment(r, from: 1))
        }
        for i in messages.indices { messages[i].stickers = placed[messages[i].guid] ?? [] }
    }

    /// Columns filename, mime_type, uti, transfer_name, is_sticker from `start`.
    private static func attachment(_ r: [Any?], from start: Int) -> Attachment {
        let raw = r[start] as? String
        let path = raw.map { $0.hasPrefix("~") ? (NSString(string: $0).expandingTildeInPath) : $0 }
        return Attachment(path: path, mime: r[start + 1] as? String, uti: r[start + 2] as? String,
                          name: r[start + 3] as? String, sticker: (r[start + 4] as? Int64 ?? 0) == 1)
    }

    private func name(for handle: String) -> String { names?.name(for: handle) ?? Self.pretty(handle) }

    /// Messages writes its write-ahead log as messages arrive: re-read the open conversation then.
    private func watch() {
        watcher?.cancel()
        let fd = Darwin.open(Self.dbPath + "-wal", O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if src.data.contains(.delete) || src.data.contains(.rename) { self.watch() } // checkpointed: watch the new one
                self.scheduleReload()
            }
        }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        watcher = src
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, let id = self.open?.chatID else { return }
            if let c = self.load(id), c != self.open { self.open = c }
        }
    }

    // MARK: Sending

    /// Asks Messages to send `text` to the open conversation. Shows it at once as "Sending…".
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let c = open else { return }
        sendError = nil
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let guid = c.guid.replacingOccurrences(of: "\"", with: "")
        var error: NSDictionary?
        let ok = NSAppleScript(source: "tell application \"Messages\" to send \"\(escaped)\" to chat id \"\(guid)\"")?
            .executeAndReturnError(&error) != nil
        if !ok {
            let n = error?[NSAppleScript.errorNumber] as? Int ?? 0
            sendError = n == -1743 ? "Allow Dynamic Peninsula to control Messages in System Settings" : "Messages couldn't send it"
            return
        }
        let p = Message(id: -Int64(pending.count + 1), text: text, mine: true, date: Date(), sender: nil, attachment: false, status: .sending)
        pending.append(p)
        open?.messages.append(p)
        scheduleReload()
    }

    // MARK: Reacting

    /// Sends a tapback on a message through Messages; nil opens the message's menu in Messages for any emoji.
    func react(_ tapback: Tapback?, to message: Message) {
        guard let c = open, !reacting, message.id > 0, let i = c.messages.firstIndex(of: message) else { return }
        let occurrence = c.messages[(i + 1)...].filter { $0.mine == message.mine && $0.text == message.text }.count
        sendError = nil
        reacting = true
        Task {
            let error = await TapbackSender.react(tapback, to: message, in: c, occurrence: occurrence)
            reacting = false
            if open?.chatID == c.chatID { sendError = error }
            scheduleReload()
        }
    }

    // MARK: Helpers

    private static func dbDate(_ d: Date) -> Int64 { Int64(d.timeIntervalSinceReferenceDate * 1e9) }
    private static func date(_ v: Int64) -> Date {
        Date(timeIntervalSinceReferenceDate: v > 1_000_000_000_000 ? Double(v) / 1e9 : Double(v))
    }

    /// The message text: the `text` column, or (newer macOS) the typedstream `attributedBody`.
    private static func text(_ text: String?, _ body: Data?) -> String? {
        if let text, !text.isEmpty { return text }
        guard let body else { return nil }
        return (NSUnarchiver.unarchiveObject(with: body) as? NSAttributedString)?.string
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "+15551234567" → "+1 (555) 123-4567"; anything else as it is.
    static func pretty(_ handle: String) -> String {
        let d = handle.filter(\.isNumber)
        guard handle.hasPrefix("+1"), d.count == 11 else { return handle }
        let a = Array(d)
        return "+1 (\(String(a[1...3]))) \(String(a[4...6]))-\(String(a[7...10]))"
    }

    private func rows(_ sql: String, _ args: [Int64] = []) -> [[Any?]] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, a) in args.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), a) }
        var result: [[Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [Any?] = []
            for i in 0..<sqlite3_column_count(stmt) {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row.append(sqlite3_column_int64(stmt, i))
                case SQLITE_TEXT: row.append(String(cString: sqlite3_column_text(stmt, i)))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, i))
                    row.append(n > 0 ? Data(bytes: sqlite3_column_blob(stmt, i), count: n) : nil)
                default: row.append(nil)
                }
            }
            result.append(row)
        }
        return result
    }
}

/// Contact names for phone numbers and emails. Messages keeps numbers as "+15551234567" and contacts have them as typed,
/// so numbers are compared by their last 10 digits.
@MainActor
final class ContactNames {
    private var byPhone: [String: String] = [:]
    private var byEmail: [String: String] = [:]
    private var loaded = false

    func load() {
        guard !loaded else { return }
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                guard granted else { return }
                Task { @MainActor in self?.load() }
            }
            return
        case .authorized: break
        default:
            if CNContactStore.authorizationStatus(for: .contacts).rawValue != 4 { return } // .limited (macOS 15) also works
        }
        loaded = true
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey,
                    CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        var phones: [String: String] = [:], emails: [String: String] = [:]
        try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
            let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let name = !c.nickname.isEmpty ? c.nickname : !full.isEmpty ? full : c.organizationName
            guard !name.isEmpty else { return }
            for p in c.phoneNumbers { phones[String(p.value.stringValue.filter(\.isNumber).suffix(10))] = name }
            for e in c.emailAddresses { emails[(e.value as String).lowercased()] = name }
        }
        byPhone = phones; byEmail = emails
    }

    func name(for handle: String) -> String? {
        handle.contains("@") ? byEmail[handle.lowercased()] : byPhone[String(handle.filter(\.isNumber).suffix(10))]
    }
}
