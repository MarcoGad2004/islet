import AppKit

/// Search in the notch (DESIGN.md "Search"): the text, the sections it finds, the selection, and what the keys do.
@MainActor @Observable
final class SearchModel {
    struct Section: Identifiable, Equatable {
        enum Style: Equatable { case recents, topHit, list, calc, none }
        var id: String
        var title: String?
        var style: Style
        var items: [SearchItem]
    }

    /// The field's text. Setting it re-runs the search.
    var text = "" { didSet { if text != oldValue { update() } } }
    private(set) var sections: [Section] = []
    /// Every selectable row, in order.
    private(set) var rows: [SearchItem] = []
    private(set) var selection = 0
    /// The field has the cursor. Until then the panel keeps the letters typed (DESIGN.md "Typing while it opens").
    var fieldReady = false
    /// Bumped to ask the field to take the cursor (and put it after the text).
    private(set) var focusRequest = 0

    @ObservationIgnored let index = SearchIndex()
    @ObservationIgnored private let files = SearchFiles()
    @ObservationIgnored private var fileResults: [SearchItem] = []
    @ObservationIgnored private var remembered: [String: Date] = SearchModel.loadRemembered()
    /// Set by the store: closes the island (opening a result, Esc on an empty field).
    @ObservationIgnored var close: (() -> Void)?
    /// Set by the store: opens the conversation with one of these numbers / emails in the notch; false when there isn't one.
    @ObservationIgnored var openConversation: (([String]) -> Bool)?
    /// Set by the store: the results changed, so the body's height may have.
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        files.onResults = { [weak self] text, items in
            guard let self, text == self.text.trimmingCharacters(in: .whitespaces) else { return }
            self.fileResults = items
            self.rebuild(keepSelection: true)
        }
    }

    var selected: SearchItem? { rows.indices.contains(selection) ? rows[selection] : nil }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Opening

    /// Fresh search, starting with `initial` (a letter typed in the panel).
    func begin(_ initial: String = "") {
        index.refreshApps()
        index.refreshShortcuts()
        index.refreshContacts()
        remembered = Self.loadRemembered()
        fieldReady = false
        fileResults = []
        if text == initial { update() } else { text = initial }
        focusRequest += 1
    }

    func end() {
        files.stop()
        fieldReady = false
    }

    // MARK: Results

    private func update() {
        let t = text.trimmingCharacters(in: .whitespaces)
        // Keep the last files that still match while the index looks (about 0.2 s), so the list doesn't jump.
        if t.count < 2 { fileResults = [] }
        files.search(t)
        rebuild(keepSelection: false)
    }

    private func rebuild(keepSelection: Bool) {
        let previous = selected?.id
        let raw = text.trimmingCharacters(in: .whitespaces)
        var out: [Section] = []
        if raw.isEmpty {
            out.append(Section(id: "recents", title: nil, style: .recents, items: index.recentApps(remembered: remembered)))
        } else if let (action, who) = ContactAction.parse(raw), case let people = contactActions(action, who), !people.isEmpty {
            // "call mom": the contacts as that action, the best first (DESIGN.md "Search", Contacts).
            out.append(Section(id: "top", title: "Top hit", style: .topHit, items: [people[0]]))
            if people.count > 1 { out.append(Section(id: "Contacts", title: "Contacts", style: .list, items: Array(people.dropFirst().prefix(3)))) }
        } else if let v = SearchCalculator.evaluate(raw) {
            out.append(Section(id: "calc", title: "Calculator", style: .calc,
                               items: [SearchItem(id: "calc:" + raw, kind: .calc, name: SearchCalculator.format(v), detail: raw,
                                                  url: SearchIndex.calculatorURL)]))
        } else {
            let q = SearchMatch.query(raw)
            var scored: [SearchItem] = []
            func add(_ items: [SearchItem], bonus: Double) {
                for var it in items {
                    // A contact also matches on its nickname or company, at a little less.
                    let alias = it.aliases.compactMap { SearchMatch.match($0, q) }.max { $0.score < $1.score }
                    guard let m = SearchMatch.match(it.name, q) ?? alias.map({ (score: $0.score - 4, marks: [Int]()) }) else { continue }
                    let used = max(it.lastUsed ?? .distantPast, remembered[it.id] ?? .distantPast)
                    it.marks = m.marks
                    it.score += m.score + bonus + SearchMatch.recency(used == .distantPast ? nil : used)
                        + (remembered[it.id] != nil ? 6 : 0)
                    scored.append(it)
                }
            }
            add(index.apps, bonus: 6)
            add(index.contacts, bonus: 4)
            add(index.shortcuts, bonus: 0)
            add(SearchIndex.settingsItems(), bonus: 1)
            add(fileResults, bonus: -4)
            scored.sort { $0.score > $1.score }
            if let top = scored.first {
                out.append(Section(id: "top", title: "Top hit", style: .topHit, items: [top]))
                for (kind, title) in [(SearchItem.Kind.app, "Applications"), (.contact, "Contacts"), (.shortcut, "Shortcuts"), (.file, "Files"), (.setting, "Settings")] {
                    let items = scored.filter { $0.kind == kind && $0.id != top.id }.prefix(3)
                    if !items.isEmpty { out.append(Section(id: title, title: title, style: .list, items: Array(items))) }
                }
            } else {
                out.append(Section(id: "none", title: nil, style: .none, items: []))
            }
        }
        if !raw.isEmpty {
            out.append(Section(id: "more", title: "More", style: .list, items: [
                SearchItem(id: "spotlight", kind: .spotlight, name: "Search “\(raw)” in Spotlight", detail: raw),
                SearchItem(id: "web", kind: .web, name: "Search the web for “\(raw)”", detail: raw),
            ]))
        }
        sections = out
        rows = out.flatMap(\.items)
        // The first row is selected; a row picked by hand stays picked while late results (files) come in.
        if keepSelection, selection != 0, let previous, let i = rows.firstIndex(where: { $0.id == previous }) {
            selection = i
        } else {
            selection = 0
        }
        onChange?()
    }

    /// The contacts matching `who` that can do `action`, as "Call Mom" rows.
    private func contactActions(_ action: ContactAction, _ who: String) -> [SearchItem] {
        let q = SearchMatch.query(who)
        var found: [SearchItem] = []
        for c in index.contacts where c.contactActions.contains(action) {
            let alias = c.aliases.compactMap { SearchMatch.match($0, q) }.max { $0.score < $1.score }
            guard let m = SearchMatch.match(c.name, q) ?? alias.map({ (score: $0.score - 4, marks: [Int]()) }) else { continue }
            var it = c
            it.score = m.score + (remembered[c.id] != nil ? 6 : 0)
            found.append(it)
        }
        return found.sorted { $0.score > $1.score }.map { c in
            var it = c
            it.action = action
            it.id = "\(action.rawValue):\(c.id)"
            it.name = "\(action.verb) \(c.name)"
            // The verb isn't part of the match: the name's letters, shifted past "Call ".
            it.marks = []
            return it
        }
    }

    // MARK: Height (DESIGN.md "Search": field 52, results up to 8 rows, footer 28)

    enum Metrics {
        static let field: CGFloat = 52
        static let hairline: CGFloat = 1
        static let footer: CGFloat = 28
        static let label: CGFloat = 22
        static let row: CGFloat = 34
        static let topHit: CGFloat = 52
        static let calc: CGFloat = 60
        static let none: CGFloat = 34
        static let recents: CGFloat = 86
        static let listPadding: CGFloat = 10
        static let maxList: CGFloat = 300
        static var maxBody: CGFloat { field + hairline + maxList + footer }
    }

    var listHeight: CGFloat {
        typealias M = Metrics
        if isEmpty { return M.recents }
        var h = M.listPadding
        for s in sections {
            switch s.style {
            case .recents: h += M.recents
            case .none: h += M.none
            case .topHit: h += M.label + M.topHit
            case .calc: h += M.label + M.calc
            case .list: h += M.label + CGFloat(s.items.count) * M.row
            }
        }
        return h
    }

    var visibleListHeight: CGFloat { min(listHeight, Metrics.maxList) }
    var bodyHeight: CGFloat { Metrics.field + (isEmpty ? 0 : Metrics.hairline) + visibleListHeight + Metrics.footer }

    // MARK: Keys

    func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        selection = (selection + by + rows.count) % rows.count
    }

    /// ⌘↑ ⌘↓: the first row of the previous or next section.
    func jumpSection(_ by: Int) {
        guard let current = selected, let s = sections.firstIndex(where: { $0.items.contains(current) }) else { return }
        var i = s + by
        while sections.indices.contains(i) {
            if let first = sections[i].items.first, let r = rows.firstIndex(of: first) { selection = r; return }
            i += by
        }
    }

    func select(_ item: SearchItem) { if let i = rows.firstIndex(of: item) { selection = i } }

    /// Tab: the field takes the selected name.
    func complete() {
        guard let s = selected, [.app, .contact, .shortcut, .file, .setting].contains(s.kind) else { return }
        text = s.name
        focusRequest += 1
    }

    /// Return (or a click): open it, run it, copy it. ⌘Return shows a file or app in Finder.
    func activate(_ item: SearchItem? = nil, reveal: Bool = false) {
        guard let it = item ?? selected else { return }
        let ws = NSWorkspace.shared
        if let action = it.action { perform(action, on: it); return }
        close?()
        switch it.kind {
        case .app, .file:
            guard let url = it.url else { return }
            remember(it)
            if reveal { ws.activateFileViewerSelecting([url]); return }
            if it.kind == .app {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                ws.openApplication(at: url, configuration: config)
            } else {
                ws.open(url)
            }
        case .contact:
            // The person in Contacts, where Message, Call, FaceTime and Email each use the right number.
            remember(it)
            if let url = it.url { ws.open(url) }
        case .setting:
            remember(it)
            if let url = it.url { ws.open(url) }
        case .shortcut:
            remember(it)
            let id = it.detail
            Task.detached { _ = SearchIndex.run("/usr/bin/shortcuts", ["run", id]) }
        case .calc:
            copy(it.name.replacingOccurrences(of: ",", with: ""))
        case .spotlight:
            SearchShortcut.shared.handOff(it.detail)
        case .web:
            if let url = WebSearchEngine.current.url(for: it.detail) { ws.open(url) }
        }
    }

    // MARK: A contact's actions

    /// Message opens your conversation with them in the notch when there is one, else Messages. Call goes through your
    /// iPhone (macOS asks first), FaceTime opens FaceTime, Email a new message in your mail app. Islet sends nothing.
    func perform(_ action: ContactAction, on c: SearchItem) {
        remember(c)
        let phone = c.phone.map { String($0.filter { $0.isNumber || $0 == "+" }) }
        var url: URL?
        switch action {
        case .message:
            if openConversation?(c.handles) == true { return }
            url = phone.flatMap { URL(string: "sms:" + $0) } ?? c.email.flatMap { URL(string: "imessage:" + $0) }
        case .call: url = phone.flatMap { URL(string: "tel:" + $0) }
        case .faceTime: url = (phone ?? c.email).flatMap { URL(string: "facetime:" + $0) }
        case .email: url = c.email.flatMap { URL(string: "mailto:" + $0) }
        }
        close?()
        if let url { NSWorkspace.shared.open(url) }
    }

    /// ⌘C: copies the selected file (as a file) or the answer.
    func copySelected() -> Bool {
        guard let it = selected else { return false }
        switch it.kind {
        case .calc: copy(it.name.replacingOccurrences(of: ",", with: "")); return true
        case .file:
            guard let url = it.url else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            return true
        default: return false
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    // MARK: Remembering what was opened (this Mac only)

    private static let rememberedKey = "searchOpened"

    private static func loadRemembered() -> [String: Date] {
        (UserDefaults.standard.dictionary(forKey: rememberedKey) as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func remember(_ it: SearchItem) {
        // "call:contact:…" is remembered as the contact.
        let id = it.action.map { a in String(it.id.dropFirst(a.rawValue.count + 1)) } ?? it.id
        remembered[id] = Date()
        // The 200 most recent are enough.
        let kept = remembered.sorted { $0.value > $1.value }.prefix(200)
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value.timeIntervalSince1970) }), forKey: Self.rememberedKey)
    }
}
