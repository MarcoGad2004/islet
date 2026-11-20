import AppKit
import Foundation

/// Low Power, Automatic or High Power, as in System Settings > Battery > Energy Mode, for the power source in use.
///
/// Reading is free (`pmset -g`). Changing it needs root, and macOS has no public API for it, so (owner's decision,
/// 2026-11-20) the first change asks for an admin password once and installs a narrow sudoers rule that lets this
/// account run exactly `pmset -b|-c powermode 0|1|2` without one. Every later change is instant. Settings > General
/// can remove the rule.
@MainActor @Observable
final class PowerModeController {
    enum Mode: Int, CaseIterable { case automatic = 0, low = 1, high = 2 }

    static let shared = PowerModeController()

    /// nil while unknown, or on a Mac without energy modes.
    private(set) var mode: Mode?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var permissionInstalled = PowerModeController.ruleInstalled

    static let rulePath = "/etc/sudoers.d/islet-powermode"
    private static let pmset = "/usr/bin/pmset"
    static var ruleInstalled: Bool { FileManager.default.fileExists(atPath: rulePath) }

    func refresh() {
        Task {
            let m = await Self.read()
            if !busy { mode = m }
        }
    }

    /// Sets the mode for the source in use: `-c` on the power adapter, `-b` on battery.
    func set(_ new: Mode, onAC: Bool) {
        guard !busy, new != mode else { return }
        let before = mode
        mode = new // show it straight away; put it back if it fails
        busy = true
        error = nil
        Task {
            let flag = onAC ? "-c" : "-b"
            var ok = await Self.runSudo(flag: flag, mode: new)
            if !ok && !Self.ruleInstalled {
                if await Self.installRule() {
                    permissionInstalled = true
                    ok = await Self.runSudo(flag: flag, mode: new)
                } else {
                    error = "Not changed: needs your admin password once."
                }
            } else if !ok {
                error = new == .high && !onAC ? "High Power isn't available on battery on this Mac." : "Couldn't change the power mode."
            }
            busy = false
            mode = ok ? await Self.read() ?? new : before
        }
    }

    /// Removes the sudoers rule (asks for the admin password).
    func removePermission() {
        Task {
            _ = await Self.admin("/bin/rm -f \(Self.rulePath)")
            permissionInstalled = Self.ruleInstalled
        }
    }

    // MARK: Plumbing

    private nonisolated static func read() async -> Mode? {
        let out = await run(pmset, ["-g"])?.output ?? ""
        // `pmset -g` lists the settings in use for the current source; "powermode" only appears on Macs that have it.
        for line in out.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == "powermode", let n = Int(parts[1]) { return Mode(rawValue: n) }
        }
        return nil
    }

    private nonisolated static func runSudo(flag: String, mode: Mode) async -> Bool {
        // -n: never prompt; without the rule this just fails.
        await run("/usr/bin/sudo", ["-n", pmset, flag, "powermode", "\(mode.rawValue)"])?.status == 0
    }

    /// Writes the rule to a temporary file, checks it with visudo, and installs it root-owned 0440. Only for a plain
    /// account name, so nothing odd can reach the rule or the shell.
    private static func installRule() async -> Bool {
        let user = NSUserName()
        guard !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { return false }
        let commands = ["-b", "-c"].flatMap { f in (0...2).map { "\(pmset) \(f) powermode \($0)" } }.joined(separator: ", ")
        let rule = "# Installed by Islet: lets \(user) switch the Energy Mode without a password. Remove in Islet's Settings.\n"
            + "\(user) ALL=(root) NOPASSWD: \(commands)\n"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("islet-powermode-\(UUID().uuidString)")
        guard (try? rule.write(to: tmp, atomically: true, encoding: .utf8)) != nil else { return false }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let script = "/usr/sbin/visudo -cf '\(tmp.path)' && /usr/bin/install -m 0440 -o root -g wheel '\(tmp.path)' \(rulePath)"
        return await admin(script)
    }

    /// Runs a shell command as root behind the standard macOS admin prompt.
    private static func admin(_ command: String) async -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        return await Task.detached {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            return err == nil
        }.value
    }

    private nonisolated static func run(_ path: String, _ args: [String]) async -> (status: Int32, output: String)? {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
