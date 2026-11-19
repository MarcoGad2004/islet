import AppKit

/// AirDrop receiving mode (the `DiscoverableMode` preference of sharingd) and a way to open AirDrop to send.
/// sharingd must be restarted after the write for macOS to apply it (verified in Finder's AirDrop window).
@MainActor @Observable
final class AirDropController {
    enum Mode: String, CaseIterable, Identifiable {
        case off = "Off", contacts = "Contacts Only", everyone = "Everyone"
        var id: String { rawValue }
        var title: String { self == .off ? "Receiving Off" : rawValue }
        var icon: String { self == .off ? "xmark.circle" : (self == .contacts ? "person.crop.circle" : "person.2.circle") }
    }

    private(set) var mode = Mode.contacts
    /// The last non-off mode, restored by the tile's toggle.
    private var lastOn = Mode.contacts

    func refresh() {
        let out = Self.run("/usr/bin/defaults", ["read", "com.apple.sharingd", "DiscoverableMode"])
        mode = Mode(rawValue: out) ?? .contacts
        if mode != .off { lastOn = mode }
    }

    func set(_ new: Mode) {
        _ = Self.run("/usr/bin/defaults", ["write", "com.apple.sharingd", "DiscoverableMode", "-string", new.rawValue])
        // sharingd only reads the preference when it starts (verified on macOS 27: the value changes but AirDrop
        // does not until the daemon restarts). launchd brings it straight back.
        _ = Self.run("/usr/bin/killall", ["sharingd"])
        mode = new
        if new != .off { lastOn = new }
    }

    func toggle() { set(mode == .off ? lastOn : .off) }

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
