import Foundation

// Shared by Dynamic Peninsula and its fan helper (RESEARCH.md "Mac Stats", spike results): the helper runs as root
// through `SMAppService.daemon` and is the only thing that writes the SMC.

enum FanHelperInfo {
    static let machService = "com.marcogad.islet.fanhelper"
    static let plistName = "com.marcogad.islet.fanhelper.plist"
    static let teamID = "L4Y6A9NY9T"
    /// Raised when the protocol changes, so an older helper still registered is replaced.
    static let version = 1

    /// Only Dynamic Peninsula, signed by its own team, may talk to the helper; and the app only trusts that helper.
    static let appRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "L4Y6A9NY9T" and identifier "com.marcogad.islet""#
    static let helperRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "L4Y6A9NY9T" and identifier "com.marcogad.islet.fanhelper""#

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
