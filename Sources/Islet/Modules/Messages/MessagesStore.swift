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
    #endif

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
            sendError = n == -1743 ? "Allow Islet to control Messages in System Settings" : "Messages couldn't send it"
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
