import OSLog
import AppKit
import Contacts
import SQLite3
import SwiftUI

/// Messages conversations in the notch (DESIGN.md "Messages", RESEARCH.md Q32-Q38).
///
/// Reads Messages' history (`~/Library/Messages/chat.db`, read only; needs Full Disk Access), names people from
/// Contacts, and shows them read only: to reply, the conversation's button opens it in Messages (owner's decision,
/// 2026-11-23: stability over sending from the notch). Islet never controls Messages or goes on the network for it.
/// Messages' database is private and may change with macOS: everything here fails quietly to "open Messages instead".
@MainActor @Observable
final class MessagesStore {
    static let enabledKey = "messagesInNotch"

    struct Message: Identifiable, Equatable {
        enum Status: Equatable, Sendable { case none, sent, delivered, read(Date), failed }
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
        /// Sent as an iMessage (blue), not SMS / RCS (green). Messages colours each bubble by how it went.
        var iMessage = true
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
        /// Incoming messages Messages hasn't marked read.
        var unread: Int
        var id: Int64 { chatID }
        var initial: String { String(title.first(where: { $0.isLetter || $0.isNumber }) ?? "#") }
    }

    /// Chats with something new first, then the other recent ones.
    private(set) var inbox: [ChatSummary] = []
    /// Chats with unread messages, as Messages' badge counts them: the panel's messages pill shows when there are any.
    private(set) var unreadCount = 0

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    private static let log = Logger(subsystem: "com.marcogad.islet", category: "messages")
    /// All reading happens on its own queue, never on the main thread (see `MessagesDB`).
    @ObservationIgnored private let db = MessagesDB()
    @ObservationIgnored private var connected = false
    @ObservationIgnored private var inboxWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var inboxTask: Task<Void, Never>?
    @ObservationIgnored private var inboxRetry: Task<Void, Never>?
    @ObservationIgnored private var lastLoggedUnread = -1
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var names: ContactNames?
    @ObservationIgnored private var chatHandles: [Int64: [String]] = [:]

    /// Whether the history can be read (Full Disk Access). Once it can, this never waits.
    var available: Bool {
        guard enabled else { return false }
        if !connected { connected = db.sync { $0.connect() } }
        return connected
    }

    private func loadNames() {
        names = names ?? ContactNames()
        names?.load()
    }
    private var book: NameBook { names?.book ?? NameBook() }

    // MARK: Finding a conversation

    /// The chat a Messages notification came from.
    func chatID(for item: NotificationItem) -> Int64? {
        guard available else { return nil }
        let body = item.body
        return db.sync { $0.chatID(forNotificationText: body) }
    }

    /// The chat a Messages notification came from, looked up in the background (opening it from a click).
    func findChat(for item: NotificationItem) async -> Int64? {
        guard available else { return nil }
        let body = item.body
        return await db.read { $0.chatID(forNotificationText: body) }
    }

    /// Where a Messages notification's chat opens in Messages: "sms:" at the person for a one-to-one chat (it opens
    /// Messages on that conversation), Messages itself for a group or when the chat can't be found.
    func messagesURL(for item: NotificationItem) async -> URL {
        if let chat = await findChat(for: item), let t = await db.read({ $0.target(chat) }) { return Self.messagesURL(guid: t.guid, isGroup: t.isGroup) }
        return Self.appURL
    }

    static let appURL = URL(fileURLWithPath: "/System/Applications/Messages.app")

    static func messagesURL(guid: String, isGroup: Bool) -> URL {
        let parts = guid.components(separatedBy: ";")
        if !isGroup, let handle = parts.last, !handle.isEmpty,
           let url = URL(string: "sms:\(handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle)") {
            return url
        }
        return appURL
    }

    /// The one-to-one chat with someone, by any of their numbers or emails (search's Message), in the background.
    func findChat(forHandles handles: [String]) async -> Int64? {
        guard available, !handles.isEmpty else { return nil }
        return await db.read { $0.chatID(forHandles: handles) }
    }

    #if DEBUG
    /// The chat of the latest message with exactly this text (the preview opens the one with "Islet test").
    func chatID(withText text: String) -> Int64? {
        guard available else { return nil }
        return db.sync { $0.chatID(withText: text) }
    }

    /// The chat with the newest message, when there's no "Islet test".
    func latestChatID() -> Int64? {
        guard available else { return nil }
        return db.sync { $0.latestChatID() }
    }
    #endif

    /// The contact photo for a one-to-one chat, when the person has one in Contacts. Groups have none (their initial shows).
    func photo(forChat chatID: Int64) -> NSImage? {
        let handles = chatHandles[chatID] ?? {
            let h = db.sync { $0.handles(chatID) }
            chatHandles[chatID] = h
            return h
        }()
        guard handles.count == 1 else { return nil }
        return names?.photo(for: handles[0])
    }

    // MARK: The inbox

    /// Keeps the unread count (and the inbox) current as messages arrive, from Messages' write-ahead log.
    func startInbox() {
        guard enabled else { return }
        refreshInbox()
        watchInbox()
    }

    private func watchInbox() {
        inboxWatcher?.cancel()
        inboxRetry?.cancel()
        defer {
            // No log to watch yet (Messages hasn't written since it was checkpointed away): look again shortly, or
            // the unread count would stop updating for good.
            if inboxWatcher == nil {
                inboxRetry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled, let self, self.inboxWatcher == nil else { return }
                    self.refreshInbox()
                    self.watchInbox()
                }
            }
        }
        inboxWatcher = Self.watchLog { [weak self] reopened in
            guard let self else { return }
            if reopened { self.watchInbox() }
            self.inboxTask?.cancel()
            self.inboxTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.refreshInbox()
            }
        }
    }

    /// Re-reads the unread messages and the recent chats, in the background.
    func refreshInbox() {
        guard available else { inbox = []; unreadCount = 0; return }
        loadNames()
        let book = self.book
        Task {
            let result = await db.read { $0.inbox(book) }
            if result.allUnread != lastLoggedUnread {
                lastLoggedUnread = result.allUnread
                Self.log.notice("unread: \(result.allUnread) in all, \(result.chats.reduce(0) { $0 + $1.unread }) from known senders in \(result.unreadChats) chats")
            }
            if result.chats != inbox { inbox = result.chats }
            if result.unreadChats != unreadCount { unreadCount = result.unreadChats }
        }
    }

    // MARK: The open conversation

    /// Reads the conversation in the background and makes it the open one. False when it can't be read. The read
    /// used to wait on the main thread, behind an inbox refresh when one was running, and the panel stuttered.
    func openChat(_ chatID: Int64) async -> Bool {
        guard available else { return false }
        loadNames()
        let book = self.book
        guard let loaded = await db.read({ $0.conversation(chatID, book) }) else { return false }
        open = loaded
        watch()
        return true
    }

    func close() {
        watcher?.cancel(); watcher = nil
        reloadTask?.cancel()
        open = nil
    }

    func isOpen(_ chatID: Int64?) -> Bool { chatID != nil && open?.chatID == chatID }

    /// Messages writes its write-ahead log as messages arrive: re-read the open conversation then.
    private func watch() {
        watcher?.cancel()
        watcher = Self.watchLog { [weak self] reopened in
            guard let self else { return }
            if reopened { self.watch() }
            self.scheduleReload()
        }
    }

    /// Calls `changed` on the main thread when Messages writes its write-ahead log; true when it was checkpointed
    /// (deleted or replaced), when the caller should watch the new file.
    private static func watchLog(_ changed: @escaping @MainActor (Bool) -> Void) -> DispatchSourceFileSystemObject? {
        let fd = Darwin.open(MessagesDB.path + "-wal", O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler {
            let reopened = src.data.contains(.delete) || src.data.contains(.rename)
            MainActor.assumeIsolated { changed(reopened) }
        }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        return src
    }

    /// Messages writes several times per message (sent, delivered, read): wait for it to settle, read in the
    /// background, then show the result with an animation. New messages slide in at the bottom.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let id = self.open?.chatID else { return }
            let book = self.book
            let loaded = await self.db.read { $0.conversation(id, book) }
            guard !Task.isCancelled, let loaded, self.open?.chatID == id else { return }
            if loaded != self.open { withAnimation(.smooth(duration: 0.35)) { self.open = loaded } }
        }
    }

    /// "+15551234567" → "+1 (555) 123-4567"; anything else as it is.
    static func pretty(_ handle: String) -> String { MessagesDB.pretty(handle) }
}

/// Contact names for phone numbers and emails. Messages keeps numbers as "+15551234567" and contacts have them as typed,
/// so numbers are compared by their last 10 digits.
@MainActor
final class ContactNames {
    private var byPhone: [String: String] = [:]
    private var byEmail: [String: String] = [:]
    /// Contact photo thumbnails, by contact, and which contact each number or email belongs to.
    private var photoData: [String: Data] = [:]
    private var photoByPhone: [String: String] = [:]
    private var photoByEmail: [String: String] = [:]
    private var photos: [String: NSImage] = [:]
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
                    CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
        var phones: [String: String] = [:], emails: [String: String] = [:]
        var data: [String: Data] = [:], photoPhones: [String: String] = [:], photoEmails: [String: String] = [:]
        try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
            let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let name = !c.nickname.isEmpty ? c.nickname : !full.isEmpty ? full : c.organizationName
            guard !name.isEmpty else { return }
            for p in c.phoneNumbers { phones[String(p.value.stringValue.filter(\.isNumber).suffix(10))] = name }
            for e in c.emailAddresses { emails[(e.value as String).lowercased()] = name }
            guard let thumb = c.thumbnailImageData else { return }
            data[c.identifier] = thumb
            for p in c.phoneNumbers { photoPhones[String(p.value.stringValue.filter(\.isNumber).suffix(10))] = c.identifier }
            for e in c.emailAddresses { photoEmails[(e.value as String).lowercased()] = c.identifier }
        }
        byPhone = phones; byEmail = emails
        photoData = data; photoByPhone = photoPhones; photoByEmail = photoEmails
    }

    func photo(for handle: String) -> NSImage? {
        let id = handle.contains("@") ? photoByEmail[handle.lowercased()] : photoByPhone[String(handle.filter(\.isNumber).suffix(10))]
        guard let id else { return nil }
        if let i = photos[id] { return i }
        guard let d = photoData[id], let i = NSImage(data: d) else { return nil }
        photos[id] = i
        return i
    }

    var book: NameBook { NameBook(byPhone: byPhone, byEmail: byEmail) }

    func name(for handle: String) -> String? {
        handle.contains("@") ? byEmail[handle.lowercased()] : byPhone[String(handle.filter(\.isNumber).suffix(10))]
    }
}
