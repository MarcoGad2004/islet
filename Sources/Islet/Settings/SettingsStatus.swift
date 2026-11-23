import AVFoundation
import SwiftUI

/// The pages of Settings, in the sidebar's order (DESIGN.md "Settings").
enum SettingsPage: String, CaseIterable, Identifiable {
    case status, general, notch, notifications, search, battery, faceUnlock, permissions, updates

    var id: String { rawValue }
    static let storageKey = "settingsPage"

    var title: String {
        switch self {
        case .status: "Dynamic Peninsula"
        case .general: "General"
        case .notch: "Notch"
        case .notifications: "Notifications"
        case .search: "Search"
        case .battery: "Battery"
        case .faceUnlock: "Face Unlock"
        case .permissions: "Permissions"
        case .updates: "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .status: "checkmark.seal.fill"
        case .general: "gearshape.fill"
        case .notch: "rectangle.topthird.inset.filled"
        case .notifications: "bell.badge.fill"
        case .search: "magnifyingglass"
        case .battery: "battery.75percent"
        case .faceUnlock: "faceid"
        case .permissions: "hand.raised.fill"
        case .updates: "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .status: .accentColor
        case .general, .updates: .gray
        case .notch: Color(white: 0.15)
        case .notifications: .red
        case .search: .blue
        case .battery: .green
        case .faceUnlock: .teal
        case .permissions: .indigo
        }
    }
}

/// Something that stops part of Islet from working, with its fix. Settings lists these on the Islet page, shows each on
/// the pages it affects, and badges those pages in the sidebar. Everything that works stays quiet.
struct SettingsIssue: Identifiable {
    let id: String
    /// The first page is where it's fixed; the others are the pages it breaks.
    let pages: [SettingsPage]
    let title: String
    let detail: String
    var actionTitle: String?
    var prominent = false
    var action: (() -> Void)?
}

/// A permission Islet asks for, and what it is for.
struct SettingsPermission: Identifiable {
    let name: String
    let purpose: String
    let allowed: Bool
    /// The features that are on and can't work without it. Empty: listed, never an issue.
    let usedBy: [Feature]
    /// What it adds to features that are on and work without it ("show names instead of numbers").
    var optional: String? = nil
    let allow: () -> Void
    var id: String { name }
    var needed: Bool { !usedBy.isEmpty }
}

/// Builds the permissions and issues from the live state of each part of Islet.
@MainActor
struct SettingsChecks {
    let face: FaceUnlockCoordinator
    let levels: LevelsController
    let media: MediaMonitor
    let focus: FocusMonitor
    let wifi: WiFiController
    let messagesAccess: MessagesAccess
    let camera: AVAuthorizationStatus
    let spotlightConflict: Bool
    let requestCamera: () -> Void

    /// The features that are on (Face Unlock counts once it's switched on).
    var on: Set<Feature> {
        var set = Set(Feature.allCases.filter { $0 != .faceUnlock && $0.isOn })
        if face.unlock.enabled { set.insert(.faceUnlock) }
        return set
    }

    private func used(_ name: String) -> [Feature] { Feature.allCases.filter { on.contains($0) && $0.needs.contains(name) } }

    var permissions: [SettingsPermission] {
        let on = self.on
        return [
            SettingsPermission(name: "Accessibility", purpose: "Volume and brightness keys, notifications and typing your password for Face Unlock",
                               allowed: face.unlock.accessibilityTrusted, usedBy: used("Accessibility"),
                               optional: on.contains(.search) ? "Search: hand questions to Siri. The island: the wider layout when the menu bar has room."
                                   : "The island: the wider layout when the menu bar has room.") { face.unlock.requestPermission() },
            SettingsPermission(name: "Full Disk Access", purpose: "Shows which Focus is on and reads your Messages conversations",
                               allowed: focus.accessGranted && !Self.debugIssues, usedBy: used("Full Disk Access")) { SystemSettings.open(SystemSettings.fullDisk) },
            SettingsPermission(name: "Contacts", purpose: "Names on messages, and people in search",
                               allowed: messagesAccess.contactsAllowed, usedBy: used("Contacts"),
                               optional: on.contains(.notifications) || on.contains(.search) ? "Names instead of numbers, and people in search." : nil) { messagesAccess.requestContacts() },
            SettingsPermission(name: "Control Messages", purpose: messagesAccess.asking ? "Answer the macOS prompt…" : "Sends your replies from the notch. Allow opens Messages to ask.",
                               allowed: messagesAccess.automationAllowed, usedBy: used("Control Messages")) { messagesAccess.requestAutomation() },
            SettingsPermission(name: "Location", purpose: "Names of nearby Wi-Fi networks. Your location is never used.",
                               allowed: wifi.locationAllowed, usedBy: [], optional: "The island: names of nearby Wi-Fi networks.") {
                if wifi.locationStatus == .notDetermined { wifi.requestLocation() } else { SystemSettings.open(SystemSettings.location) }
            },
            SettingsPermission(name: "Camera", purpose: "Face Unlock",
                               allowed: camera == .authorized, usedBy: used("Camera"), allow: requestCamera),
        ]
    }

    /// One line for a feature on the Islet page: Off, Ready, or what it still needs.
    func state(_ f: Feature) -> (text: String, ok: Bool?) {
        if f == .faceUnlock {
            if !face.faces.isReady { return ("Not set up", nil) }
            if !face.unlock.enabled { return ("Off", nil) }
        } else if !f.isOn {
            return (f.parent.map { $0.isOn ? "Off" : "Off with \($0.title)" } ?? "Off", nil)
        }
        let missing = permissions.filter { !$0.allowed && $0.usedBy.contains(f) }.map(\.name)
        if !missing.isEmpty { return ("Needs " + Self.list(missing), false) }
        if f == .search {
            if spotlightConflict { return ("Spotlight still uses \(SearchShortcutChoice.current.title)", false) }
            return ("Ready on \(SearchShortcutChoice.current.title)", true)
        }
        if f == .levels, !levels.tapActive { return ("Restart Dynamic Peninsula to start", false) }
        return ("Ready", true)
    }

    static func list(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    var issues: [SettingsIssue] {
        var list: [SettingsIssue] = []
        for p in permissions where !p.allowed && p.needed {
            var pages: [SettingsPage] = [.permissions]
            if p.usedBy.contains(where: { [.notifications, .messages].contains($0) }) { pages.append(.notifications) }
            if p.usedBy.contains(.faceUnlock) { pages.append(.faceUnlock) }
            let names = p.usedBy.map(\.title)
            let detail = Self.list(names) + (names.count > 1 ? " don't" : " doesn't") + " work without it. Turn "
                + (names.count > 1 ? "them" : "it") + " off on the Dynamic Peninsula page if you don't use " + (names.count > 1 ? "them." : "it.")
            list.append(SettingsIssue(id: "perm-" + p.name, pages: pages, title: "\(p.name) is off", detail: detail,
                                      actionTitle: "Allow…", action: p.allow))
        }
        if face.unlock.accessibilityTrusted, Feature.levels.isOn, !levels.tapActive {
            list.append(SettingsIssue(id: "keys", pages: [.permissions], title: "Volume and brightness keys aren't reaching Dynamic Peninsula",
                                      detail: "Accessibility is on, but macOS hasn't handed the keys over yet. Restarting Dynamic Peninsula fixes it.",
                                      actionTitle: "Restart Dynamic Peninsula", action: { SettingsChecks.relaunch() }))
        }
        if !media.available {
            list.append(SettingsIssue(id: "media", pages: [.permissions], title: "Now playing isn't available",
                                      detail: "Dynamic Peninsula's helper for reading what's playing couldn't start on this Mac, so music doesn't show in the notch."))
        }
        if spotlightConflict {
            list.append(SettingsIssue(id: "spotlight", pages: [.search], title: "Spotlight still uses \(SearchShortcutChoice.current.title)",
                                      detail: "Spotlight takes the keyboard first, so search doesn't open. Move Spotlight to another shortcut, or keep it there and give Dynamic Peninsula another one on the Search page.",
                                      actionTitle: "Keyboard Shortcuts…", action: { NSWorkspace.shared.open(SearchShortcut.keyboardShortcutsURL) }))
        }
        if face.unlock.enabled || face.faces.isEnrolled, !face.modelAvailable {
            list.append(SettingsIssue(id: "model", pages: [.faceUnlock], title: "The face model is missing",
                                      detail: "Face Unlock can't recognise anyone without it. Build Dynamic Peninsula again after running scripts/fetch-model.sh."))
        }
        if face.unlock.passwordRejected {
            list.append(SettingsIssue(id: "password", pages: [.faceUnlock], title: "Face Unlock is paused",
                                      detail: "The stored password wasn't accepted. Change the password on the Face Unlock page to resume."))
        }
        if case .available(let tag) = Updater.shared.state {
            list.append(SettingsIssue(id: "update", pages: [.updates], title: "Dynamic Peninsula \(Updater.plain(tag)) is ready",
                                      detail: "Dynamic Peninsula restarts when it's installed.", actionTitle: "Install and Restart", prominent: true,
                                      action: { Updater.shared.install(tag) }))
        }
        return list
    }

    /// `-IsletDebugIssues YES` shows Full Disk Access as off, to see Settings with something to fix.
    static var debugIssues: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "IsletDebugIssues")
        #else
        false
        #endif
    }

    /// Opens a fresh copy once this one has quit.
    static func relaunch() { Relauncher.restart() }
}
