import AppKit
import Contacts

/// The permission Messages in the notch adds (DESIGN.md "Messages"): Contacts, for names and photos. Reading Messages'
/// history needs Full Disk Access, which setup already asks for. The notch only shows conversations, so it never
/// controls Messages.
@MainActor @Observable
final class MessagesAccess {
    private(set) var contacts = CNContactStore.authorizationStatus(for: .contacts)

    var contactsAllowed: Bool { contacts == .authorized || contacts.rawValue == 4 } // 4: .limited (macOS 15)

    func refresh() {
        contacts = CNContactStore.authorizationStatus(for: .contacts)
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
}
