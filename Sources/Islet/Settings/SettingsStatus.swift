import AVFoundation
import SwiftUI

/// The pages of Settings, in the sidebar's order (DESIGN.md "Settings").
enum SettingsPage: String, CaseIterable, Identifiable {
    case status, general, notch, notifications, search, battery, faceUnlock, permissions, updates

    var id: String { rawValue }
    static let storageKey = "settingsPage"

    var title: String {
        switch self {
        case .status: "Islet"
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
    /// Off but nothing that's turned on uses it: listed, never an issue.
    let needed: Bool
    let allow: () -> Void
    var id: String { name }
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
    let notificationsOn: Bool
    let messagesOn: Bool
    let requestCamera: () -> Void

    private var messagesInUse: Bool { notificationsOn && messagesOn }
    private var faceInUse: Bool { face.faces.isEnrolled || face.unlock.enabled }

    var permissions: [SettingsPermission] {
        [
            SettingsPermission(name: "Accessibility", purpose: "Volume and brightness keys, the menu bar width check and typing your password for Face Unlock",
                               allowed: face.unlock.accessibilityTrusted, needed: true) { face.unlock.requestPermission() },
            SettingsPermission(name: "Full Disk Access", purpose: "Shows which Focus is on and reads your Messages conversations",
                               allowed: focus.accessGranted && !Self.debugIssues, needed: true) { SystemSettings.open(SystemSettings.fullDisk) },
            SettingsPermission(name: "Contacts", purpose: "Names on messages, and people in search",
                               allowed: messagesAccess.contactsAllowed, needed: true) { messagesAccess.requestContacts() },
            SettingsPermission(name: "Control Messages", purpose: messagesAccess.asking ? "Answer the macOS prompt…" : "Sends your replies from the notch. Allow opens Messages to ask.",
                               allowed: messagesAccess.automationAllowed, needed: messagesInUse) { messagesAccess.requestAutomation() },
            SettingsPermission(name: "Location", purpose: "Names of nearby Wi-Fi networks",
                               allowed: wifi.locationAllowed, needed: true) {
                if wifi.locationStatus == .notDetermined { wifi.requestLocation() } else { SystemSettings.open(SystemSettings.location) }
            },
            SettingsPermission(name: "Camera", purpose: "Face Unlock",
                               allowed: camera == .authorized, needed: faceInUse, allow: requestCamera),
        ]
    }

    var issues: [SettingsIssue] {
        var list: [SettingsIssue] = []
        for p in permissions where !p.allowed && p.needed {
            var pages: [SettingsPage] = [.permissions]
            let detail: String
            switch p.name {
            case "Accessibility":
                pages += faceInUse ? [.faceUnlock] : []
                detail = "Volume and brightness keys, the menu bar width check and Face Unlock don't work without it."
            case "Full Disk Access":
                pages += messagesInUse ? [.notifications] : []
                detail = "Focus and Messages conversations in the notch don't work without it."
            case "Contacts":
                pages += [.notifications, .search]
                detail = "Messages show numbers instead of names, and search can't find people."
            case "Control Messages":
                pages += [.notifications]
                detail = "Replies from the notch can't be sent without it."
            case "Location":
                detail = "The Wi-Fi page can't show the names of nearby networks without it."
            default:
                pages += [.faceUnlock]
                detail = "Face Unlock can't see you without it."
            }
            list.append(SettingsIssue(id: "perm-" + p.name, pages: pages, title: "\(p.name) is off", detail: detail,
                                      actionTitle: "Allow…", action: p.allow))
        }
        if face.unlock.accessibilityTrusted, !levels.tapActive {
            list.append(SettingsIssue(id: "keys", pages: [.permissions], title: "Volume and brightness keys aren't reaching Islet",
                                      detail: "Accessibility is on, but macOS hasn't handed the keys over yet. Restarting Islet fixes it.",
                                      actionTitle: "Restart Islet", action: { SettingsChecks.relaunch() }))
        }
        if !media.available {
            list.append(SettingsIssue(id: "media", pages: [.permissions], title: "Now playing isn't available",
                                      detail: "Islet's helper for reading what's playing couldn't start on this Mac, so music doesn't show in the notch."))
        }
        if spotlightConflict {
            list.append(SettingsIssue(id: "spotlight", pages: [.search], title: "Spotlight still uses \(SearchShortcutChoice.current.title)",
                                      detail: "Spotlight takes the keyboard first. Change its shortcut in Keyboard Shortcuts > Spotlight, or pick another one here.",
                                      actionTitle: "Keyboard Shortcuts…", action: { NSWorkspace.shared.open(SearchShortcut.keyboardShortcutsURL) }))
        }
        if faceInUse, !face.modelAvailable {
            list.append(SettingsIssue(id: "model", pages: [.faceUnlock], title: "The face model is missing",
                                      detail: "Face Unlock can't recognise anyone without it. Build Islet again after running scripts/fetch-model.sh."))
        }
        if face.unlock.passwordRejected {
            list.append(SettingsIssue(id: "password", pages: [.faceUnlock], title: "Face Unlock is paused",
                                      detail: "The stored password wasn't accepted. Change the password on the Face Unlock page to resume."))
        }
        if case .available(let tag) = Updater.shared.state {
            list.append(SettingsIssue(id: "update", pages: [.updates], title: "Islet \(Updater.plain(tag)) is ready",
                                      detail: "Islet restarts when it's installed.", actionTitle: "Install and Restart", prominent: true,
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

    /// Opens a fresh copy of Islet once this one has quit.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
