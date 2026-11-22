import AppKit
import Carbon.HIToolbox

/// The shortcut that opens search (Settings > General > "Search shortcut"; DESIGN.md "Search", "Opening").
enum SearchShortcutChoice: String, CaseIterable, Identifiable {
    case commandSpace, optionSpace, controlSpace, commandShiftSpace, off
    static let key = "searchShortcut"
    var id: String { rawValue }

    static var current: SearchShortcutChoice {
        UserDefaults.standard.string(forKey: key).flatMap(SearchShortcutChoice.init(rawValue:)) ?? .commandSpace
    }

    var title: String {
        switch self {
        case .commandSpace: "⌘Space"
        case .optionSpace: "⌥Space"
        case .controlSpace: "⌃Space"
        case .commandShiftSpace: "⇧⌘Space"
        case .off: "Off"
        }
    }

    /// Carbon modifiers for `RegisterEventHotKey`.
    var carbonModifiers: UInt32? {
        switch self {
        case .commandSpace: UInt32(cmdKey)
        case .optionSpace: UInt32(optionKey)
        case .controlSpace: UInt32(controlKey)
        case .commandShiftSpace: UInt32(cmdKey | shiftKey)
        case .off: nil
        }
    }

    /// The same, as the flags macOS stores for its own shortcuts.
    var eventFlags: UInt64 {
        switch self {
        case .commandSpace: CGEventFlags.maskCommand.rawValue
        case .optionSpace: CGEventFlags.maskAlternate.rawValue
        case .controlSpace: CGEventFlags.maskControl.rawValue
        case .commandShiftSpace: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
        case .off: 0
        }
    }
}

/// The search engine "Search the web" uses (RESEARCH.md Q43: a browser's own engine can't be read).
enum WebSearchEngine: String, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, ecosia, kagi
    static let key = "searchWebEngine"
    var id: String { rawValue }

    static var current: WebSearchEngine {
        UserDefaults.standard.string(forKey: key).flatMap(WebSearchEngine.init(rawValue:)) ?? .google
    }

    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .kagi: "Kagi"
        }
    }

    func url(for text: String) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        switch self {
        case .google: c.host = "www.google.com"; c.path = "/search"
        case .duckDuckGo: c.host = "duckduckgo.com"; c.path = "/"
        case .bing: c.host = "www.bing.com"; c.path = "/search"
        case .ecosia: c.host = "www.ecosia.org"; c.path = "/search"
        case .kagi: c.host = "kagi.com"; c.path = "/search"
        }
        c.queryItems = [URLQueryItem(name: "q", value: text)]
        return c.url
    }
}

/// Registers the search shortcut with Carbon's hot keys (no permission needed; RESEARCH.md Q44), works out whether
/// Spotlight still has ⌘Space, and hands a search over to Spotlight (Q46).
@MainActor
final class SearchShortcut {
    static let shared = SearchShortcut()
    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Presses are ignored until then: Islet itself is pressing Spotlight's shortcut.
    private var ignoreUntil = Date.distantPast

    /// Registers the chosen shortcut (again, after a change in Settings).
    func apply() {
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { SearchShortcut.shared.pressed() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard let mods = SearchShortcutChoice.current.carbonModifiers else { return }
        RegisterEventHotKey(UInt32(kVK_Space), mods, EventHotKeyID(signature: OSType(0x49534c54), id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    private func pressed() {
        guard Date() >= ignoreUntil else { return }
        onPress?()
    }

    // MARK: Spotlight's own shortcut

    /// Spotlight's "Show Spotlight search" shortcut: `com.apple.symbolichotkeys` entry 64. Missing means the default,
    /// ⌘Space, on (Q44).
    struct SpotlightShortcut { var enabled: Bool; var keyCode: Int; var flags: UInt64 }

    static func spotlightShortcut() -> SpotlightShortcut {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        guard let entry = all?["64"] as? [String: Any] else {
            return SpotlightShortcut(enabled: true, keyCode: kVK_Space, flags: CGEventFlags.maskCommand.rawValue)
        }
        let enabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) ?? 1 != 0)
        let params = ((entry["value"] as? [String: Any])?["parameters"] as? [Int]) ?? [32, kVK_Space, Int(CGEventFlags.maskCommand.rawValue)]
        let keyCode = params.count > 1 ? params[1] : kVK_Space
        let flags = params.count > 2 ? UInt64(params[2]) : CGEventFlags.maskCommand.rawValue
        return SpotlightShortcut(enabled: enabled, keyCode: keyCode, flags: flags)
    }

    /// Spotlight still answers the shortcut chosen for search, so it would take the keyboard (Settings shows a warning).
    static var spotlightConflict: Bool {
        let choice = SearchShortcutChoice.current
        guard choice != .off else { return false }
        let s = spotlightShortcut()
        let relevant: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
        return s.enabled && s.keyCode == kVK_Space && (s.flags & relevant) == choice.eventFlags
    }

    static let keyboardShortcutsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    // MARK: Handing a search to Spotlight

    /// Opens Spotlight with `text` typed in: presses Spotlight's own shortcut and types the text (needs Accessibility and
    /// Spotlight's shortcut moved off Islet's). Otherwise a Finder search window, the only search macOS opens on request.
    func handOff(_ text: String) {
        let s = Self.spotlightShortcut()
        guard AXIsProcessTrusted(), s.enabled, !Self.spotlightConflict else {
            NSWorkspace.shared.showSearchResults(forQueryString: text)
            return
        }
        ignoreUntil = Date().addingTimeInterval(1)
        Task { @MainActor in
            // Let the island close and the previous app take the keyboard back first.
            try? await Task.sleep(for: .milliseconds(250))
            Self.postKey(CGKeyCode(s.keyCode), flags: CGEventFlags(rawValue: s.flags))
            try? await Task.sleep(for: .milliseconds(350))
            Self.type(text)
        }
    }

    /// Ask Siri: Spotlight answers a question typed into it with Siri on Return (macOS 27), so Islet opens Spotlight,
    /// types the question and presses Return. Apps have no other way to reach Siri.
    func askSiri(_ text: String) {
        let s = Self.spotlightShortcut()
        guard SiriQuestion.offered else { return }
        ignoreUntil = Date().addingTimeInterval(1.2)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            Self.postKey(CGKeyCode(s.keyCode), flags: CGEventFlags(rawValue: s.flags))
            try? await Task.sleep(for: .milliseconds(350))
            Self.type(text)
            // Spotlight settles on "Ask Siri" as you type; give it a moment before Return.
            try? await Task.sleep(for: .milliseconds(450))
            Self.postKey(CGKeyCode(kVK_Return), flags: [])
        }
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Types text without the clipboard, a few characters per event.
    private static func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + 16, units.count)])
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                e?.post(tap: .cghidEventTap)
            }
            i += 16
        }
    }
}

/// When search offers Ask Siri (DESIGN.md "Search", "Ask Siri").
enum SiriQuestion {
    static let enabledKey = "searchAskSiri"

    /// Turned on, macOS 27 or later (Siri in Spotlight), Accessibility (to type into Spotlight), and Spotlight has a
    /// shortcut of its own to press.
    @MainActor static var offered: Bool {
        guard UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true else { return false }
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)) else { return false }
        return AXIsProcessTrusted() && SearchShortcut.spotlightShortcut().enabled && !SearchShortcut.spotlightConflict
    }

    /// "siri what's on today" → "what's on today" (any case; "siri," and "siri:" too). Nil without the word.
    static func prefixed(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("siri") else { return nil }
        let rest = t.dropFirst(4)
        if let c = rest.first, c.isLetter || c.isNumber { return nil } // "sirius"
        return rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
    }

    private static let starts: Set<String> = ["what", "what's", "whats", "how", "how's", "when", "why", "who", "who's", "whos",
                                              "where", "which", "can", "could", "should", "would", "is", "are", "do", "does",
                                              "did", "will", "tell", "explain"]

    /// Reads like a question: ends in "?", or starts with a question word and has more words after it.
    static func isQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("?") && t.count > 1 { return true }
        let words = t.lowercased().replacingOccurrences(of: "’", with: "'").split(separator: " ")
        guard words.count >= 2, let first = words.first else { return false }
        return starts.contains(String(first))
    }
}
