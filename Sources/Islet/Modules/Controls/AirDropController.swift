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
        mode = Mode(rawValue: Self.run("/usr/bin/defaults", ["read", "com.apple.sharingd", "DiscoverableMode"])) ?? .contacts
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

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SystemSettings {
    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
    static let wifi = "com.apple.wifi-settings-extension"
    static let bluetooth = "com.apple.BluetoothSettings"
    static let airdrop = "com.apple.AirDrop-Handoff-Settings.extension"
    static let displays = "com.apple.Displays-Settings.extension"
    static let sound = "com.apple.Sound-Settings.extension"
    static let controlCenter = "com.apple.ControlCenter-Settings.extension"
    static let location = "com.apple.preference.security?Privacy_LocationServices"
    static let fullDisk = "com.apple.preference.security?Privacy_AllFiles"
}
