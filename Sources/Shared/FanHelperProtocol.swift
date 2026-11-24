import Foundation
import Security

// Shared by Dynamic Peninsula and its fan helper (RESEARCH.md "Mac Stats", spike results): the helper runs as root
// through `SMAppService.daemon` and is the only thing that writes the SMC.

enum FanHelperInfo {
    static let machService = "com.marcogad.islet.fanhelper"
    static let plistName = "com.marcogad.islet.fanhelper.plist"
    /// Raised when the protocol changes, so an older helper still registered is replaced.
    static let version = 1

    /// Only Dynamic Peninsula may talk to the helper, and the app only trusts that helper: each must be signed by the
    /// same team as the one checking. Development builds are signed by one team and releases (Developer ID) by another,
    /// so the team comes from our own signature rather than being written here.
    static var appRequirement: String { requirement(identifier: "com.marcogad.islet") }
    static var helperRequirement: String { requirement(identifier: "com.marcogad.islet.fanhelper") }

    private static func requirement(identifier: String) -> String {
        // An unsigned build has no team: then nothing matches, and the fans can't be changed.
        let team = ownTeam() ?? "unsigned"
        return #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)" and identifier "\#(identifier)""#
    }

    /// The team that signed this process.
    static func ownTeam() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Hand the fans back when the app hasn't been heard from for this long while it holds them.
    static let heartbeatTimeout: TimeInterval = 10
    /// The app checks in this often while it holds them.
    static let heartbeatInterval: TimeInterval = 3
    /// Hand the fans back to macOS at this average CPU temperature (°C), whatever speed was set.
    static let handBackCelsius: Double = 90
}

/// Keys of the helper's status dictionary.
enum FanHelperStatus {
    static let mode = "mode"           // "automatic", "manual" or "full"
    static let rpm = "rpm"             // the target while manual
    static let reason = "reason"       // why the fans were last handed back by the helper itself, if they were
    static let version = "version"
}

@objc(IsletFanHelperProtocol)
protocol FanHelperProtocol {
    func status(reply: @escaping (NSDictionary) -> Void)
    /// Both fans at `rpm` (kept within each fan's range). Taking them over takes a few seconds the first time.
    func setSpeed(_ rpm: Double, reply: @escaping (Bool, String?) -> Void)
    func setFullSpeed(reply: @escaping (Bool, String?) -> Void)
    /// Gives the fans back to macOS.
    func setAutomatic(reply: @escaping (Bool) -> Void)
    /// The app is still there; without one every `heartbeatTimeout` seconds the helper hands the fans back.
    func heartbeat()
}
