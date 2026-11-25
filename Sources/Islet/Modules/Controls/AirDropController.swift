import AppKit

/// AirDrop: shows the receiving mode and opens Finder's AirDrop window. It cannot change the mode: the preference
/// only takes effect after sharingd restarts, which is too disruptive for a tile (M10 spike).
@MainActor @Observable
final class AirDropController {
    enum Mode: String {
        case off = "Off", contacts = "Contacts Only", everyone = "Everyone"
        /// The word Finder and System Settings use.
        var status: String { self == .off ? "No One" : (self == .contacts ? "Contacts" : "Everyone") }
    }

    private(set) var mode = Mode.contacts

    func refresh() {
        // Read in-process: this runs on every panel open, and a `defaults` process there cost a visible hitch.
        let raw = CFPreferencesCopyAppValue("DiscoverableMode" as CFString, "com.apple.sharingd" as CFString) as? String
        mode = raw.flatMap(Mode.init(rawValue:)) ?? .contacts
    }

    /// Opens a Finder window on AirDrop (Finder's Go > AirDrop shortcut).
    func openAirDrop() {
        let script = """
        tell application "Finder" to activate
        tell application "System Events" to keystroke "r" using {command down, shift down}
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }
}

enum SystemSettings {
    /// Posted when a System Settings pane is opened, so the panel gets out of its way (AppDelegate collapses it).
    static let didOpen = Notification.Name("IsletOpenedSystemSettings")

    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
        NotificationCenter.default.post(name: didOpen, object: nil)
    }
    static let wifi = "com.apple.wifi-settings-extension"
    static let bluetooth = "com.apple.BluetoothSettings"
    static let airdrop = "com.apple.AirDrop-Handoff-Settings.extension"
    static let displays = "com.apple.Displays-Settings.extension"
    static let sound = "com.apple.Sound-Settings.extension"
    static let controlCenter = "com.apple.ControlCenter-Settings.extension"
    static let location = "com.apple.preference.security?Privacy_LocationServices"
    static let fullDisk = "com.apple.preference.security?Privacy_AllFiles"
    static let battery = "com.apple.Battery-Settings.extension"
}
