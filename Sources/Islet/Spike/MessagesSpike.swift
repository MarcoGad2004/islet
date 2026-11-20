#if DEBUG
import AppKit
import Contacts
import SQLite3

/// 1.5 spike: can the notch show iMessage conversations and send a reply? (RESEARCH.md "iMessage in the notch")
/// Read-only, and it never writes message text, names or numbers to the log: only counts and yes / no.
/// Output: ~/Library/Logs/Islet-messages-spike.log. Run with `-IsletDebugShape messagesspike`.
@MainActor
final class MessagesSpike {
    private let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-messages-spike.log")
    private var out = ""
    private var db: OpaquePointer?
    /// Handles (phone numbers / emails) of the most recent chats, for the contact-name check. Never logged.
    private var recentHandles: [String] = []

    private func log(_ s: String) { out += s + "\n"; try? out.write(to: logURL, atomically: true, encoding: .utf8) }

    func run() async {
        log("# Islet messages spike \(Date())  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        database()
        await contacts()
        await scripting()
        log("\ndone")
    }

    // MARK: Reading chat.db

    private func database() {
        log("\n## Database")
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db").path
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        log("open: \(rc == SQLITE_OK ? "ok" : "failed \(rc): \(String(cString: sqlite3_errmsg(db)))")")
        guard rc == SQLITE_OK else { return }
        log("messages: \(scalar("select count(*) from message") ?? "?")")
        log("chats: \(scalar("select count(*) from chat") ?? "?")")
        let cols = rows("pragma table_info(message)").compactMap { $0[1] as? String }
        let wanted = ["text", "attributedBody", "is_from_me", "date", "handle_id", "associated_message_type", "cache_has_attachments",
                      "thread_originator_guid", "date_read", "is_read"]
        log("message columns present: " + wanted.map { "\($0)=\(cols.contains($0) ? "y" : "n")" }.joined(separator: " "))

        // The latest 300: where does the text live, and can attributedBody be decoded?
        let recent = rows("select text, attributedBody, associated_message_type, is_from_me, cache_has_attachments, date from message order by date desc limit 300")
        var textOnly = 0, bodyOnly = 0, both = 0, neither = 0, decoded = 0, decodeFailed = 0, agree = 0, reactions = 0, attachments = 0, mine = 0
        for r in recent {
            let text = (r[0] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let body = r[1] as? Data
            if (r[2] as? Int64 ?? 0) != 0 { reactions += 1 }
            if (r[3] as? Int64 ?? 0) == 1 { mine += 1 }
            if (r[4] as? Int64 ?? 0) == 1 { attachments += 1 }
            switch (text != nil, body != nil) {
            case (true, false): textOnly += 1
            case (false, true): bodyOnly += 1
            case (true, true): both += 1
            default: neither += 1
            }
            if let body {
                if let s = Self.decode(body), !s.isEmpty {
                    decoded += 1
                    if let text, s == text { agree += 1 }
                } else { decodeFailed += 1 }
            }
        }
        log("latest \(recent.count): text only \(textOnly), attributedBody only \(bodyOnly), both \(both), neither \(neither)")
        log("attributedBody decoded \(decoded), failed \(decodeFailed); decoded == text where both: \(agree) of \(both)")
        log("reactions/edits (associated_message_type != 0) \(reactions), with attachments \(attachments), sent by me \(mine)")
        if let newest = recent.first?[5] as? Int64 {
            let seconds = newest > 1_000_000_000_000 ? Double(newest) / 1e9 : Double(newest)
            let age = Date().timeIntervalSince(Date(timeIntervalSinceReferenceDate: seconds))
            log("newest message: \(Int(age / 60)) min ago (date is \(newest > 1_000_000_000_000 ? "ns" : "s") since 2001)")
        }

        // The 20 most recent chats: 1:1 or group, named or not, which service.
        let chats = rows("""
            select c.ROWID, c.style, ifnull(length(c.display_name), 0), c.service_name,
                   (select count(*) from chat_handle_join h where h.chat_id = c.ROWID), max(m.date)
            from chat c join chat_message_join j on j.chat_id = c.ROWID join message m on m.ROWID = j.message_id
            group by c.ROWID order by max(m.date) desc limit 20
            """)
        var styles: [String: Int] = [:], services: [String: Int] = [:], named = 0
        for c in chats {
            let style = (c[1] as? Int64).map { $0 == 43 ? "group" : $0 == 45 ? "one-to-one" : "style \($0)" } ?? "?"
            styles[style, default: 0] += 1
            services[(c[3] as? String) ?? "?", default: 0] += 1
            if (c[2] as? Int64 ?? 0) > 0 { named += 1 }
        }
        log("recent \(chats.count) chats: \(styles.map { "\($0.key) \($0.value)" }.sorted().joined(separator: ", ")); named groups \(named)")
        log("services: \(services.map { "\($0.key) \($0.value)" }.sorted().joined(separator: ", "))")
        let ids = chats.compactMap { $0[0] as? Int64 }.map(String.init).joined(separator: ",")
        if !ids.isEmpty {
            recentHandles = rows("select distinct h.id from handle h join chat_handle_join j on j.handle_id = h.ROWID where j.chat_id in (\(ids))")
                .compactMap { $0[0] as? String }
            let emails = recentHandles.filter { $0.contains("@") }.count
            log("their handles: \(recentHandles.count) (\(emails) emails, \(recentHandles.count - emails) phone numbers)")
        }
        // Does the database change as messages arrive (the write-ahead log), so it can be watched instead of polled?
        let wal = path + "-wal"
        let attrs = try? FileManager.default.attributesOfItem(atPath: wal)
        if let m = attrs?[.modificationDate] as? Date { log("chat.db-wal last changed \(Int(Date().timeIntervalSince(m))) s ago") }
        else { log("chat.db-wal: none") }
    }

    /// The message text kept in `attributedBody` (a typedstream NSAttributedString) on newer macOS.
    static func decode(_ data: Data) -> String? {
        (NSUnarchiver.unarchiveObject(with: data) as? NSAttributedString)?.string
    }

    private func scalar(_ sql: String) -> String? { rows(sql).first?.first.map { "\($0 ?? "nil")" } }

    private func rows(_ sql: String) -> [[Any?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log("query failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var result: [[Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [Any?] = []
            for i in 0..<sqlite3_column_count(stmt) {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row.append(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: row.append(sqlite3_column_double(stmt, i))
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

    // MARK: Contact names

    private func contacts() async {
        log("\n## Contacts")
        let store = CNContactStore()
        var status = CNContactStore.authorizationStatus(for: .contacts)
        log("status before: \(status.rawValue) (0 notDetermined, 2 denied, 3 authorized, 4 limited)")
        if status == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
            status = CNContactStore.authorizationStatus(for: .contacts)
            log("status after asking: \(status.rawValue)")
        }
        guard status == .authorized || status.rawValue == 4, !recentHandles.isEmpty else { return }
        // Messages keeps numbers as "+15551234567"; contacts have them however they were typed. Compare digits (the last
        // 10) and lower-cased emails, from one pass over all contacts.
        let keys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        var phones = Set<String>(), emails = Set<String>(), total = 0
        try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
            total += 1
            for p in c.phoneNumbers { phones.insert(String(p.value.stringValue.filter(\.isNumber).suffix(10))) }
            for e in c.emailAddresses { emails.insert((e.value as String).lowercased()) }
        }
        log("contacts: \(total), phone numbers \(phones.count), emails \(emails.count)")
        var found = 0
        for h in recentHandles {
            if h.contains("@") ? emails.contains(h.lowercased()) : phones.contains(String(h.filter(\.isNumber).suffix(10))) { found += 1 }
        }
        log("recent handles with a contact name: \(found) of \(recentHandles.count)")
    }

    // MARK: Sending one test message (owner's OK, 2026-11-20)

    /// Sends "Islet test" to the owner's own iMessage address (the one their chats use most), then watches chat.db for
    /// the sent row. Logs whether it went, never the address.
    func sendTest() async {
        log("# Islet messages send test \(Date())")
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { log("open failed"); return }
        guard let login = rows("select account_login from chat where service_name = 'iMessage' and account_login is not null group by account_login order by count(*) desc limit 1").first?.first as? String else {
            log("no own iMessage address found"); return
        }
        let me = login.hasPrefix("E:") || login.hasPrefix("P:") ? String(login.dropFirst(2)) : login
        log("own address: \(me.contains("@") ? "an email" : "a phone number")")
        let before = Date()
        let attempts = [
            ("participant", "tell application \"Messages\" to send \"Islet test\" to participant \"\(me)\" of (1st account whose service type = iMessage)"),
            ("buddy", "tell application \"Messages\" to send \"Islet test\" to buddy \"\(me)\" of (1st service whose service type = iMessage)"),
        ]
        var sent = false
        for (name, source) in attempts where !sent {
            var error: NSDictionary?
            let t0 = Date()
            if NSAppleScript(source: source)?.executeAndReturnError(&error) != nil {
                log("send via \(name): ok in \(Int(Date().timeIntervalSince(t0) * 1000)) ms"); sent = true
            } else {
                log("send via \(name) failed: \(error?[NSAppleScript.errorNumber] ?? "?") \(error?[NSAppleScript.errorMessage] ?? "")")
            }
        }
        guard sent else { return }
        let since = Int64(before.timeIntervalSinceReferenceDate * 1e9) - 2_000_000_000
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            let r = rows("select is_sent, is_delivered, error, is_from_me from message where is_from_me = 1 and date > \(since) and text = 'Islet test' order by date desc limit 1")
            if let row = r.first {
                log("in chat.db: is_sent \(row[0] ?? "nil"), is_delivered \(row[1] ?? "nil"), error \(row[2] ?? "nil") after \(Int(Date().timeIntervalSince(before))) s")
                if (row[1] as? Int64) == 1 || ((row[2] as? Int64) ?? 0) != 0 { break }
            }
        }
        log("done")
    }

    // MARK: Sending (Apple Events to Messages)

    private func scripting() async {
        log("\n## Messages scripting (read only: no message is sent)")
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MobileSMS").isEmpty
        log("Messages running: \(running)")
        var error: NSDictionary?
        let r = NSAppleScript(source: "tell application \"Messages\" to count of chats")?.executeAndReturnError(&error)
        if let r { log("count of chats via Apple Events: \(r.int32Value)") }
        else { log("Apple Events failed: \(error?[NSAppleScript.errorNumber] ?? "?") \(error?[NSAppleScript.errorMessage] ?? "")") }
        var error2: NSDictionary?
        let services = NSAppleScript(source: "tell application \"Messages\" to get service type of every account")?.executeAndReturnError(&error2)
        if let services {
            let n = services.numberOfItems
            log("accounts: \((n > 0 ? (1...n) : 1...0).compactMap { services.atIndex($0)?.stringValue }.joined(separator: ", "))")
        } else { log("accounts failed: \(error2?[NSAppleScript.errorNumber] ?? "?")") }
    }
}
#endif
