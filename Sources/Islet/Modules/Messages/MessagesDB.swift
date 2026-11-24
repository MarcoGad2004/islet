import AppKit
import OSLog
import SQLite3

/// A tapback, as Messages stores it on a message (`associated_message_type` 2000-2005; RESEARCH.md Q57-Q60). Shown,
/// never sent: the notch only views conversations.
enum Tapback: Int, CaseIterable, Identifiable {
    case love = 2000, like, dislike, laugh, emphasize, question

    var id: Int { rawValue }
    var emoji: String { ["❤️", "👍", "👎", "😂", "‼️", "❓"][rawValue - 2000] }
}

/// Contact names for numbers and emails, as a copy the background reader can use (`ContactNames` lives on the main thread).
struct NameBook: Sendable {
    var byPhone: [String: String] = [:]
    var byEmail: [String: String] = [:]

    /// Their name in Contacts, if they're in it.
    func known(_ handle: String) -> String? {
        handle.contains("@") ? byEmail[handle.lowercased()] : byPhone[String(handle.filter(\.isNumber).suffix(10))]
    }
    /// Their name in Contacts, else the number or email.
    func name(_ handle: String) -> String { known(handle) ?? MessagesDB.pretty(handle) }
}

/// Messages' history (`~/Library/Messages/chat.db`, read only), read on its own queue: Messages writes to it several
/// times for every message sent or received, and reading it on the main thread stalled the panel's animations.
/// Everything here runs on `queue`; the main thread asks through `read` (async) or, for quick lookups, `sync`.
final class MessagesDB: @unchecked Sendable {
    typealias Message = MessagesStore.Message
    typealias Attachment = MessagesStore.Attachment
    typealias Reaction = MessagesStore.Reaction
    typealias Conversation = MessagesStore.Conversation
    typealias ChatSummary = MessagesStore.ChatSummary

    struct Inbox: Sendable {
        var chats: [ChatSummary]
        /// Chats with unread messages from known senders (what Messages' badge counts).
        var unreadChats: Int
        /// Unread messages from anyone, for the log.
        var allUnread: Int
    }

    private let queue = DispatchQueue(label: "com.marcogad.islet.messages.db", qos: .userInitiated)
    private var db: OpaquePointer?
    private var known: [Int64: Bool] = [:]
    private var handlesByChat: [Int64: [String]] = [:]
    private lazy var hasEmojiColumn: Bool =
        rows("pragma table_info(message)").contains { ($0[1] as? String) == "associated_message_emoji" }
    private lazy var hasStickerColumn: Bool =
        rows("pragma table_info(attachment)").contains { ($0[1] as? String) == "is_sticker" }
    /// `chat.is_filtered` where Messages keeps it (its own known/unknown verdict), else nothing.
    private lazy var chatFilterColumn: String =
        rows("pragma table_info(chat)").contains { ($0[1] as? String) == "is_filtered" } ? "c.is_filtered" : "null"

    static var path: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db").path
    }

    /// Waits for the queue: only for small lookups the main thread needs at once.
    func sync<T>(_ work: (MessagesDB) -> T) -> T { queue.sync { work(self) } }

    /// Runs on the queue without blocking the caller.
    func read<T: Sendable>(_ work: @escaping @Sendable (MessagesDB) -> T) async -> T {
        await withCheckedContinuation { done in queue.async { done.resume(returning: work(self)) } }
    }

    /// Opens the database on first use. False without Full Disk Access.
    func connect() -> Bool {
        if db != nil { return true }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(Self.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return false
        }
        db = handle
        return true
    }

    // MARK: Lookups

    /// The chat a Messages notification came from: the newest incoming message (in the last 10 minutes) whose text
    /// matches the notification's, else the newest incoming one.
    func chatID(forNotificationText body: String) -> Int64? {
        let since = Self.dbDate(Date().addingTimeInterval(-600))
        let recent = rows("""
            select j.chat_id, m.text, m.attributedBody from message m join chat_message_join j on j.message_id = m.ROWID
            where m.is_from_me = 0 and m.date > ? and m.associated_message_type = 0 order by m.date desc limit 30
            """, [since])
        let wanted = Self.clean(body)
        for r in recent {
            let text = Self.clean(Self.text(r[1] as? String, r[2] as? Data) ?? "")
            if !wanted.isEmpty, !text.isEmpty, text == wanted || text.hasPrefix(wanted) || wanted.hasPrefix(text) { return r[0] as? Int64 }
        }
        return recent.first?[0] as? Int64
    }

    /// The one-to-one chat with someone, by any of their numbers or emails (search's Message). The newest such chat when
    /// there are several (iMessage and SMS). Numbers compare by their last 10 digits, like contact names.
    func chatID(forHandles handles: [String]) -> Int64? {
        func key(_ h: String) -> String { h.contains("@") ? h.lowercased() : String(h.filter(\.isNumber).suffix(10)) }
        let wanted = Set(handles.map(key).filter { !$0.isEmpty })
        let sql = "select c.ROWID, h.id from chat c join chat_handle_join j on j.chat_id = c.ROWID join handle h on h.ROWID = j.handle_id "
            + "where (select count(*) from chat_handle_join x where x.chat_id = c.ROWID) = 1 order by c.ROWID desc"
        return rows(sql).first { ($0[1] as? String).map { wanted.contains(key($0)) } ?? false }?[0] as? Int64
    }

    #if DEBUG
    func chatID(withText text: String) -> Int64? {
        rows("select j.chat_id, m.text from message m join chat_message_join j on j.message_id = m.ROWID where m.is_from_me = 1 order by m.date desc limit 200")
            .first { ($0[1] as? String) == text }?[0] as? Int64
    }

    func latestChatID() -> Int64? {
        rows("select j.chat_id from message m join chat_message_join j on j.message_id = m.ROWID order by m.date desc limit 1").first?[0] as? Int64
    }
    #endif

    /// The people in a chat (numbers and emails), remembered: they don't change.
    func handles(_ chat: Int64) -> [String] {
        if let h = handlesByChat[chat] { return h }
        let h = rows("select h.id from handle h join chat_handle_join j on j.handle_id = h.ROWID where j.chat_id = ?", [chat])
            .compactMap { $0[0] as? String }
        handlesByChat[chat] = h
        return h
    }

    /// Incoming messages in a chat that Messages still shows unread.
    func unreadInMessages(_ chat: Int64) -> Int {
        Int(rows("""
            select count(*) from message m join chat_message_join j on j.message_id = m.ROWID
            where j.chat_id = ? and m.is_from_me = 0 and m.is_read = 0 and m.associated_message_type = 0 and m.item_type = 0
            """, [chat]).first?[0] as? Int64 ?? 0)
    }

    // MARK: The inbox

    /// Someone in the chat is in Contacts, or you've written in it (a reply makes a sender known, as in Messages).
    private func isKnown(_ chat: Int64, _ names: NameBook) -> Bool {
        if let k = known[chat] { return k }
        var k = handles(chat).contains { names.known($0) != nil }
        if !k {
            k = !rows("""
                select 1 from message m join chat_message_join j on j.message_id = m.ROWID
                where j.chat_id = ? and m.is_from_me = 1 limit 1
                """, [chat]).isEmpty
        }
        // Known stays known; unknown is asked again next time (you may reply or add them).
        if k { known[chat] = true }
        return k
    }

    /// The unread messages and the recent chats.
    func inbox(_ names: NameBook) -> Inbox {
        // What Messages counts on its badge: chats with unread incoming messages, however old (reading on any device
        // clears them, as it syncs), from known senders only. A reply counts as reading what came before it (the island
        // can send but can't mark messages read in Messages). Like "Filter Unknown Senders", a chat is known when someone in it
        // is in Contacts or you've written in it; spam and deleted chats never count.
        var unread: [Int64: Int] = [:]
        var all = 0
        for r in rows("""
            select j.chat_id, count(*), \(chatFilterColumn) from message m join chat_message_join j on j.message_id = m.ROWID
            join chat c on c.ROWID = j.chat_id
            where m.is_from_me = 0 and m.is_read = 0 and m.associated_message_type = 0 and m.item_type = 0
              and m.date > coalesce((select max(r.date) from message r join chat_message_join rj on rj.message_id = r.ROWID
                                     where rj.chat_id = j.chat_id and r.is_from_me = 1), 0)
            group by j.chat_id
            """) {
            guard let chat = r[0] as? Int64, let n = r[1] as? Int64, n > 0 else { continue }
            all += Int(n)
            guard isKnown(chat, names) else { continue }
            unread[chat] = Int(n)
        }
        let recent = rows("""
            select j.chat_id, max(m.date) from message m join chat_message_join j on j.message_id = m.ROWID
            where m.associated_message_type = 0 and m.date > ? group by j.chat_id order by max(m.date) desc limit 12
            """, [Self.dbDate(Date().addingTimeInterval(-30 * 86400))])
        var list: [ChatSummary] = recent.compactMap { r in
            guard let chat = r[0] as? Int64 else { return nil }
            return summary(chat, unread: unread[chat] ?? 0, names)
        }
        // An unread chat older than the recent ones still makes the list.
        for (chat, n) in unread where !list.contains(where: { $0.chatID == chat }) {
            if let s = summary(chat, unread: n, names) { list.append(s) }
        }
        list.sort { ($0.unread > 0) != ($1.unread > 0) ? $0.unread > 0 : $0.date > $1.date }
        // Messages' badge counts chats, not messages.
        return Inbox(chats: list, unreadChats: unread.count, allUnread: all)
    }

    private func summary(_ chat: Int64, unread: Int, _ names: NameBook) -> ChatSummary? {
        guard let title = title(of: chat, names) else { return nil }
        guard let r = rows("""
            select m.text, m.attributedBody, m.is_from_me, m.cache_has_attachments, m.date
            from message m join chat_message_join j on j.message_id = m.ROWID
            where j.chat_id = ? and m.associated_message_type = 0 order by m.date desc limit 1
            """, [chat]).first else { return nil }
        var text = (Self.text(r[0] as? String, r[1] as? Data) ?? "").replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = (r[3] as? Int64) == 1 ? "Attachment" : "" }
        if (r[2] as? Int64) == 1, !text.isEmpty { text = "You: " + text }
        return ChatSummary(chatID: chat, title: title, preview: text, date: Self.date(r[4] as? Int64 ?? 0), unread: unread)
    }

    /// A chat's name: its own, or the people in it.
    private func title(of chat: Int64, _ names: NameBook) -> String? {
        guard let c = rows("select display_name from chat where ROWID = ?", [chat]).first else { return nil }
        let handles = handles(chat)
        let display = (c[0] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return display ?? (handles.isEmpty ? "Messages" : handles.map(names.name).joined(separator: ", "))
    }

    // MARK: A conversation

    /// The chat and its latest 50 messages, with their tapbacks, files and stickers.
    func conversation(_ chatID: Int64, _ names: NameBook) -> Conversation? {
        guard let c = rows("select guid, display_name, style, service_name from chat where ROWID = ?", [chatID]).first,
              let guid = c[0] as? String else { return nil }
        let handles = handles(chatID)
        let isGroup = (c[2] as? Int64) == 43
        let service = (c[3] as? String) ?? "iMessage"
        let display = (c[1] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title = display ?? (handles.isEmpty ? "Messages" : handles.map(names.name).joined(separator: ", "))
        let raw = rows("""
            select m.ROWID, m.text, m.attributedBody, m.is_from_me, m.date, m.cache_has_attachments, m.is_delivered, m.error, h.id,
                   m.guid, m.date_read, m.service
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
                : (r[6] as? Int64) == 1 ? .delivered : .sent
            return Message(id: id, guid: r[9] as? String ?? "", text: text, mine: mine, date: Self.date(r[4] as? Int64 ?? 0),
                           sender: isGroup && !mine ? (r[8] as? String).map(names.name) : nil,
                           attachment: attachment, status: status, iMessage: !Self.isText(r[11] as? String))
        }
        addReactions(to: &messages, chatID: chatID)
        addAttachments(to: &messages, chatID: chatID)
        // Newer macOS keeps someone's iMessages and texts in one chat whose service isn't "iMessage": what the latest
        // message went as says how the next one will (as Messages shows it), else the chat's own service.
        let latest = raw.first { ($0[11] as? String).map { !$0.isEmpty } ?? false }?[11] as? String
        return Conversation(chatID: chatID, guid: guid, title: title, isGroup: isGroup, people: handles.count + 1,
                            iMessage: !Self.isText(latest ?? service), messages: messages)
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

    // MARK: Helpers

    /// A green-bubble service: SMS or RCS. Anything else (iMessage, or a merged chat's "any") is blue.
    static func isText(_ service: String?) -> Bool {
        guard let service else { return false }
        return ["SMS", "RCS"].contains(service.uppercased())
    }

    static func dbDate(_ d: Date) -> Int64 { Int64(d.timeIntervalSinceReferenceDate * 1e9) }
    static func date(_ v: Int64) -> Date {
        Date(timeIntervalSinceReferenceDate: v > 1_000_000_000_000 ? Double(v) / 1e9 : Double(v))
    }

    /// The message text: the `text` column, or (newer macOS) the typedstream `attributedBody`.
    static func text(_ text: String?, _ body: Data?) -> String? {
        if let text, !text.isEmpty { return text }
        guard let body else { return nil }
        return (NSUnarchiver.unarchiveObject(with: body) as? NSAttributedString)?.string
    }

    static func clean(_ s: String) -> String {
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
        guard connect(), let db else { return [] }
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
