import AppKit
import Contacts

/// The two permissions Messages in the notch adds (DESIGN.md "Messages"): Contacts, for names, and Automation for
/// Messages, to send replies. Reading Messages' history needs Full Disk Access, which setup already asks for.
@MainActor @Observable
final class MessagesAccess {
    nonisolated static let messagesBundleID = "com.apple.MobileSMS"

    private(set) var contacts = CNContactStore.authorizationStatus(for: .contacts)
    /// nil until checked; checking needs Messages to be open.
    private(set) var automation: OSStatus?
    private(set) var asking = false

    var contactsAllowed: Bool { contacts == .authorized || contacts.rawValue == 4 } // 4: .limited (macOS 15)
    var automationAllowed: Bool { automation == noErr }
    var messagesOpen: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.messagesBundleID).isEmpty }

    func refresh() {
        contacts = CNContactStore.authorizationStatus(for: .contacts)
        // Only looks (never asks); answers procNotFound (-600) while Messages is closed, so keep the last answer then.
        guard messagesOpen else { return }
        automation = Self.determine(ask: false)
    }

    func requestContacts() {
        if contacts == .notDetermined {
            CNContactStore().requestAccess(for: .contacts) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        } else {
            SystemSettings.open("com.apple.preference.security?Privacy_Contacts")
        }
    }

    /// Asks macOS whether Islet may control Messages, opening Messages in the background first if it's closed (the
    /// question needs it running). Once denied, macOS doesn't ask again: then it opens the Automation settings.
    func requestAutomation() {
        if automation == OSStatus(errAEEventNotPermitted) {
            SystemSettings.open("com.apple.preference.security?Privacy_Automation")
            return
        }
        guard !asking else { return }
        asking = true
        Task { [weak self] in
            if self?.messagesOpen == false, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.messagesBundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.hides = true
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
                try? await Task.sleep(for: .seconds(1))
            }
            // Blocks until the person answers the macOS prompt: off the main thread.
            let status = await Task.detached { Self.determine(ask: true) }.value
            self?.automation = status
            self?.asking = false
        }
    }

    nonisolated private static func determine(ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let id = messagesBundleID
        let created = id.withCString { AECreateDesc(typeApplicationBundleID, $0, id.utf8.count, &target) }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
    }
}
