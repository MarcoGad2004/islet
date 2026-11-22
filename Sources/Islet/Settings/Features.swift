import Foundation

/// What Islet does that you can turn off (DESIGN.md "Features"). The island itself (now playing, charging, the controls)
/// is always on. A feature that's off is never asked permissions for, and nothing it needs shows as a problem.
enum Feature: String, CaseIterable, Identifiable {
    case levels, notifications, messages, focus, search, faceUnlock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .levels: "Volume and brightness"
        case .notifications: "Notifications"
        case .messages: "Messages"
        case .focus: "Focus"
        case .search: "Search"
        case .faceUnlock: "Face Unlock"
        }
    }

    var detail: String {
        switch self {
        case .levels: "The keys show their level in the notch instead of the middle of the screen."
        case .notifications: "Banners come out of the notch instead of the top-right corner."
        case .messages: "Click a message to read the conversation and reply from the notch."
        case .focus: "Shows which Focus is on when it changes."
        case .search: "Apps, files, people, Shortcuts and settings from the notch, and questions handed to Siri."
        case .faceUnlock: "Unlocks the lock screen when it sees you. Weaker than Touch ID."
        }
    }

    /// The permissions it can't work without.
    var needs: [String] {
        switch self {
        case .levels, .notifications: ["Accessibility"]
        case .messages: ["Full Disk Access", "Contacts", "Control Messages"]
        case .focus: ["Full Disk Access"]
        case .search: []
        case .faceUnlock: ["Camera", "Accessibility"]
        }
    }

    /// Messages lives inside Notifications: it's off while they are.
    var parent: Feature? { self == .messages ? .notifications : nil }

    static let levelsKey = "levelsInNotch"
    static let focusKey = "focusInNotch"
    /// The search shortcut before search was turned off, to come back to.
    static let lastSearchShortcutKey = "searchShortcutLast"

    /// Face Unlock's switch belongs to its coordinator; the rest are plain settings.
    @MainActor var isOn: Bool {
        let d = UserDefaults.standard
        switch self {
        case .levels: return d.object(forKey: Self.levelsKey) as? Bool ?? true
        case .notifications: return d.object(forKey: NotificationWatcher.enabledKey) as? Bool ?? true
        case .messages: return Feature.notifications.isOn && (d.object(forKey: MessagesStore.enabledKey) as? Bool ?? true)
        case .focus: return d.object(forKey: Self.focusKey) as? Bool ?? true
        case .search: return SearchShortcutChoice.current != .off
        case .faceUnlock: return d.bool(forKey: "faceUnlockEnabled")
        }
    }

    /// Turns it on or off (not Face Unlock, which has its own set-up).
    @MainActor
    func set(_ on: Bool) {
        let d = UserDefaults.standard
        switch self {
        case .levels: d.set(on, forKey: Self.levelsKey)
        case .notifications: d.set(on, forKey: NotificationWatcher.enabledKey)
        case .messages: d.set(on, forKey: MessagesStore.enabledKey)
        case .focus: d.set(on, forKey: Self.focusKey)
        case .search:
            let now = SearchShortcutChoice.current
            if on, now == .off {
                let last = d.string(forKey: Self.lastSearchShortcutKey).flatMap(SearchShortcutChoice.init(rawValue:))
                d.set((last ?? .commandSpace).rawValue, forKey: SearchShortcutChoice.key)
            } else if !on, now != .off {
                d.set(now.rawValue, forKey: Self.lastSearchShortcutKey)
                d.set(SearchShortcutChoice.off.rawValue, forKey: SearchShortcutChoice.key)
            }
            SearchShortcut.shared.apply()
        case .faceUnlock: break
        }
    }
}
