#if DEBUG
import AppKit
import Carbon.HIToolbox

/// Search spike: can Islet run its own search from the notch? (RESEARCH.md "Search from the notch")
/// Logs counts, timings and yes / no only, never file names or search results.
/// Output: ~/Library/Logs/Islet-search-spike.log. Run with `-IsletDebugShape searchspike`; Islet quits when it's done.
///
/// It briefly posts keystrokes: ⌃⌥⌘Space and ⌘Space (each closed again with Esc if Spotlight opened), and "abc" into
/// its own small panel, only once that panel has the keyboard, so nothing is typed into another app.
@MainActor
final class SearchSpike {
    private let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-search-spike.log")
    private var out = ""
    private func log(_ s: String) { out += s + "\n"; try? out.write(to: logURL, atomically: true, encoding: .utf8) }
    private func ms(_ start: Date) -> String { String(format: "%.0f ms", Date().timeIntervalSince(start) * 1000) }
    private func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    func run() async {
        log("# Islet search spike \(Date())  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        log("accessibility trusted: \(AXIsProcessTrusted())")
        await apps()
        await files()
        shortcuts()
        handlers()
        spotlightShortcutSetting()
        await typing()
        await hotKeys()
        log("\ndone")
        NSApp.terminate(nil)
    }

    // MARK: Spotlight index

    /// Runs one metadata query and waits for the first full gather.
    private func query(_ predicate: NSPredicate, scopes: [Any], attrs: [String] = []) async -> (NSMetadataQuery, String) {
        let q = NSMetadataQuery()
        q.predicate = predicate
        q.searchScopes = scopes
        if !attrs.isEmpty { q.valueListAttributes = attrs }
        let start = Date()
        let took: String = await withCheckedContinuation { cont in
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in
                if let token { NotificationCenter.default.removeObserver(token) }
                cont.resume(returning: String(format: "%.0f ms", Date().timeIntervalSince(start) * 1000))
            }
            q.start()
        }
        q.disableUpdates()
        return (q, took)
    }

    private func apps() async {
        log("\n## Apps")
        let (q, took) = await query(NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'"),
                                    scopes: [NSMetadataQueryLocalComputerScope])
        let items = (0..<q.resultCount).compactMap { q.result(at: $0) as? NSMetadataItem }
        let paths = items.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
        let used = items.filter { $0.value(forAttribute: "kMDItemLastUsedDate") != nil }.count
        let inApps = paths.filter { $0.hasPrefix("/Applications/") || $0.hasPrefix("/System/Applications/") }.count
        log("index query: \(q.resultCount) apps in \(took); \(inApps) in /Applications or /System/Applications; \(used) have a last-used date")
        let known = ["Safari", "Messages", "Calculator", "System Settings", "Xcode"]
        log("found: " + known.map { name in "\(name)=\(paths.contains { $0.hasSuffix("/\(name).app") } ? "y" : "n")" }.joined(separator: " "))
        q.stop()

        // The plain alternative: list the app folders.
        var start = Date()
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", fm.homeDirectoryForCurrentUser.path + "/Applications"]
        let listed = dirs.flatMap { d in ((try? fm.contentsOfDirectory(atPath: d)) ?? []).filter { $0.hasSuffix(".app") } }
        log("listing the app folders: \(listed.count) apps in \(ms(start))")

        start = Date()
        for p in paths.prefix(50) { _ = NSWorkspace.shared.icon(forFile: p) }
        log("icons for \(min(50, paths.count)) apps: \(ms(start))")
    }

    private func files() async {
        log("\n## Files (home folder, names only; counts, never names)")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for text in ["b", "bu", "bud", "budget", "no", "invoice", "xcd"] {
            let p = NSPredicate(format: "kMDItemFSName LIKE[cd] %@", "*\(text)*")
            let (q, took) = await query(p, scopes: [NSMetadataQueryUserHomeScope])
            let paths = (0..<q.resultCount).compactMap { (q.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String }
            func n(_ dir: String) -> Int { paths.filter { $0.hasPrefix(home + "/" + dir + "/") }.count }
            log("\"\(text)\": \(q.resultCount) in \(took) (Documents \(n("Documents")), Desktop \(n("Desktop")), Downloads \(n("Downloads")), Library \(n("Library")))")
            q.stop()
        }
        // Word starts only, the way the design ranks: does the index do it faster than a substring match?
        let (q, took) = await query(NSPredicate(format: "kMDItemDisplayName BEGINSWITH[cd] %@", "bud"), scopes: [NSMetadataQueryUserHomeScope])
        log("\"bud\" as a prefix: \(q.resultCount) in \(took)")
        q.stop()
        // Cancelling: start a query per keystroke and stop the previous one, as typing would.
        let start = Date()
        var last: NSMetadataQuery?
        for text in ["i", "in", "inv", "invo"] {
            last?.stop()
            let q = NSMetadataQuery()
            q.predicate = NSPredicate(format: "kMDItemFSName LIKE[cd] %@", "*\(text)*")
            q.searchScopes = [NSMetadataQueryUserHomeScope]
            q.start()
            last = q
        }
        let final = last!
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: final, queue: .main) { _ in
                if let token { NotificationCenter.default.removeObserver(token) }
                cont.resume()
            }
        }
        log("four keystrokes, each stopping the last query: final results after \(ms(start)) (\(final.resultCount))")
        final.stop()
    }

    // MARK: Shortcuts

    private func shortcuts() {
        log("\n## Shortcuts")
        let start = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["list", "--show-identifiers"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let lines = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
            let withID = lines.filter { $0.contains("(") && $0.hasSuffix(")") }.count
            log("shortcuts list: exit \(p.terminationStatus), \(lines.count) shortcuts (\(withID) with an identifier) in \(ms(start))")
        } catch {
            log("shortcuts list: failed \(error.localizedDescription)")
        }
        let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Shortcuts/Shortcuts.sqlite").path
        log("Shortcuts database readable (icons and colours): \(FileManager.default.isReadableFile(atPath: db))")
    }

    // MARK: Web search and System Settings

    private func handlers() {
        log("\n## Handlers (looked up, nothing opened)")
        for s in ["x-web-search://?islet", "https://www.example.com", "x-apple.systempreferences:com.apple.wifi-settings-extension"] {
            let app = URL(string: s).flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            log("\(s.prefix(30)): \(app?.lastPathComponent ?? "no handler")")
        }
    }

    // MARK: ⌘Space

    private func spotlightShortcutSetting() {
        log("\n## Spotlight's shortcut setting")
        let d = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        if let e = d?["64"] as? [String: Any] {
            let params = ((e["value"] as? [String: Any])?["parameters"] as? [Int]) ?? []
            log("entry 64 (Show Spotlight search): enabled \(e["enabled"] ?? "?"), parameters \(params)")
        } else {
            log("entry 64 (Show Spotlight search): not set, so the default (⌘Space, on). dictionary readable: \(d != nil)")
        }
    }

    /// Does a key panel that doesn't activate Islet get every letter, even typed the moment it opens?
    private func typing() async {
        log("\n## Typing into a non-activating panel")
        guard AXIsProcessTrusted() else { log("skipped: no Accessibility, so no keystrokes posted"); return }
        let panel = SpikePanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        let field = NSTextField(frame: NSRect(x: 8, y: 8, width: 224, height: 24))
        panel.contentView?.addSubview(field)
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 120, y: screen.frame.maxY - 120)) }
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let start = Date()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(field)
        log("panel key: \(panel.isKeyWindow) after \(ms(start)); Islet active: \(NSApp.isActive); front app stays: \(NSWorkspace.shared.frontmostApplication?.localizedName == front)")
        guard panel.isKeyWindow else { log("skipped typing: the panel isn't key"); panel.orderOut(nil); return }
        // Straight away, as if typed right after the shortcut.
        for ch in "abc" { post(text: String(ch)) }
        await pause(0.4)
        log("typed abc at once: field has \(field.stringValue.count) of 3 letters, in order: \(field.stringValue == "abc")")
        panel.orderOut(nil)
    }

    nonisolated(unsafe) static var hotKeyHits: [UInt32] = []

    private func hotKeys() async {
        log("\n## Global shortcuts")
        guard AXIsProcessTrusted() else { log("skipped: no Accessibility"); return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handler: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            SearchSpike.hotKeyHits.append(id.id)
            return noErr
        }, 1, &spec, nil, &handler)

        // 1: a free combination, to prove the mechanism.
        // 2: ⌘Space while Spotlight still has it: who gets it?
        let tests: [(UInt32, UInt32, CGEventFlags, String)] = [
            (1, UInt32(controlKey | optionKey | cmdKey), [.maskControl, .maskAlternate, .maskCommand], "⌃⌥⌘Space"),
            (2, UInt32(cmdKey), [.maskCommand], "⌘Space"),
        ]
        for (id, mods, flags, name) in tests {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(kVK_Space), mods, EventHotKeyID(signature: OSType(0x49534c54), id: id), GetApplicationEventTarget(), 0, &ref)
            Self.hotKeyHits.removeAll()
            let start = Date()
            postKey(UInt32(kVK_Space), flags: flags)
            await pause(0.6)
            let spotlight = spotlightWindow()
            log("\(name): register status \(status); Islet got it: \(Self.hotKeyHits.contains(id)) (\(ms(start)) window); Spotlight opened: \(spotlight != nil)\(spotlight.map { ", at \($0)" } ?? "")")
            if spotlight != nil { postKey(UInt32(kVK_Escape), flags: []); await pause(0.4) }
            if let ref { UnregisterEventHotKey(ref) }
        }
        if let handler { RemoveEventHandler(handler) }
    }

    // MARK: By hand (`-IsletDebugShape searchkeys`): the owner presses the keys, so no Accessibility is needed

    /// For 3 minutes: ⌃⌥⌘Space and ⌘Space are registered. Each press opens a small key panel under the notch, the
    /// way search would; type "abc" straight away and wait. Logs which shortcut reached Islet, how fast the panel took
    /// the keyboard, and whether every letter arrived (length and "is it abc", never the text). Then it asks Spotlight to
    /// search through `NSWorkspace.showSearchResults` and logs what opened.
    func runKeys() async {
        log("# Islet search spike, by hand \(Date())")
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handler: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hit = id.id
            DispatchQueue.main.async { NotificationCenter.default.post(name: SearchSpike.hotKeyNote, object: nil, userInfo: ["id": hit]) }
            return noErr
        }, 1, &spec, nil, &handler)
        var refs: [EventHotKeyRef?] = []
        for (id, mods, name) in [(UInt32(1), UInt32(controlKey | optionKey | cmdKey), "⌃⌥⌘Space"), (2, UInt32(cmdKey), "⌘Space")] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(kVK_Space), mods, EventHotKeyID(signature: OSType(0x49534c54), id: id), GetApplicationEventTarget(), 0, &ref)
            log("register \(name): status \(status)")
            refs.append(ref)
        }

        let panel = SpikePanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .black
        let field = NSTextField(frame: NSRect(x: 12, y: 10, width: 296, height: 24))
        field.placeholderString = "Type abc"
        panel.contentView?.addSubview(field)
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 160, y: screen.frame.maxY - 90)) }

        var pressed: Date?
        var firstLetter: Date?
        var lastChange = Date()
        let changes = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: field, queue: .main) { _ in
            MainActor.assumeIsolated {
                if firstLetter == nil { firstLetter = Date() }
                lastChange = Date()
            }
        }
        let hits = NotificationCenter.default.addObserver(forName: Self.hotKeyNote, object: nil, queue: .main) { note in
            let id = note.userInfo?["id"] as? UInt32 ?? 0
            MainActor.assumeIsolated {
                let front = NSWorkspace.shared.frontmostApplication?.localizedName
                let start = Date()
                pressed = start; firstLetter = nil; lastChange = start
                field.stringValue = ""
                panel.orderFrontRegardless()
                panel.makeKey()
                panel.makeFirstResponder(field)
                self.log("\n\(id == 1 ? "⌃⌥⌘Space" : "⌘Space") reached Islet; panel key \(panel.isKeyWindow) after \(self.ms(start)); Islet active: \(NSApp.isActive); front app unchanged: \(NSWorkspace.shared.frontmostApplication?.localizedName == front)")
            }
        }
        log("waiting 3 minutes for key presses")
        let end = Date().addingTimeInterval(180)
        while Date() < end {
            await pause(0.1)
            if let p = pressed, Date().timeIntervalSince(lastChange) > 2.5 {
                let v = field.stringValue
                log("typed: \(v.count) letters, is abc: \(v == "abc"), first letter \(firstLetter.map { String(format: "%.0f ms", $0.timeIntervalSince(p) * 1000) } ?? "never") after the shortcut")
                pressed = nil
                panel.orderOut(nil)
            }
        }
        NotificationCenter.default.removeObserver(changes)
        NotificationCenter.default.removeObserver(hits)
        refs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }
        if let handler { RemoveEventHandler(handler) }

        log("\n## Handing a search to Spotlight")
        let before = Set(ownersOnScreen())
        let ok = NSWorkspace.shared.showSearchResults(forQueryString: "islet")
        await pause(1.5)
        let opened = Set(ownersOnScreen()).subtracting(before)
        log("showSearchResults returned \(ok); new windows from: \(opened.isEmpty ? "none" : opened.sorted().joined(separator: ", ")); Spotlight window: \(spotlightWindow() ?? "none")")
        log("\ndone")
        NSApp.terminate(nil)
    }

    static let hotKeyNote = Notification.Name("SearchSpikeHotKey")

    private func ownersOnScreen() -> [String] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { $0[kCGWindowOwnerName as String] as? String }
    }

    private func spotlightWindow() -> String? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list where (w[kCGWindowOwnerName as String] as? String) == "Spotlight" {
            guard let b = w[kCGWindowBounds as String] as? [String: Any], let r = CGRect(dictionaryRepresentation: b as CFDictionary), r.height > 30 else { continue }
            return "x \(Int(r.minX)) y \(Int(r.minY)) w \(Int(r.width)) h \(Int(r.height)), layer \(w[kCGWindowLayer as String] ?? "?")"
        }
        return nil
    }

    private func postKey(_ key: UInt32, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    private func post(text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        let chars = Array(text.utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
            e?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            e?.post(tap: .cghidEventTap)
        }
    }
}

private final class SpikePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
#endif
