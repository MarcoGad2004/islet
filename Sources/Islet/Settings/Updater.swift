import AppKit

/// Updates Islet from the newest GitHub release of this repo. Only runs when the user clicks "Check for updates".
/// The repo is private, so it goes through the GitHub CLI (`gh`), which uses the owner's own login; no token is
/// stored in the app. The release carries `Islet.dmg`; the new app replaces this one after Islet quits.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(String)
        case downloading(String)
        case failed(String)
    }

    static let repo = "MarcoGad2004/islet"
    private(set) var state = State.idle

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var ghPath: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Installing replaces the running app, so it only makes sense for a copy in Applications.
    private var installable: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Applications/") || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func check() {
        guard ghPath != nil else {
            state = .failed("Updates need the GitHub CLI (brew install gh, then gh auth login).")
            return
        }
        state = .checking
        let gh = ghPath!
        Task {
            let out = await Self.run(gh, ["release", "view", "--repo", Self.repo, "--json", "tagName", "--jq", ".tagName"])
            guard out.status == 0 else {
                state = .failed("Couldn't reach GitHub: \(out.text.isEmpty ? "no release found" : out.text)")
                return
            }
            let tag = out.text
            state = Self.isNewer(tag, than: currentVersion) ? .available(tag) : .upToDate
        }
    }

    func install(_ tag: String) {
        guard installable, let gh = ghPath else {
            state = .failed("Move Islet to the Applications folder to update it in place.")
            return
        }
        state = .downloading(tag)
        Task {
            do { try await Self.download(tag: tag, gh: gh, dest: Bundle.main.bundlePath) }
            catch { state = .failed((error as? UpdateError)?.message ?? error.localizedDescription); return }
            NSApp.terminate(nil)
        }
    }

    // MARK: - Work off the main actor

    struct UpdateError: Error { let message: String }

    nonisolated private static func download(tag: String, gh: String, dest: String) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("islet-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let dl = await run(gh, ["release", "download", tag, "--repo", repo, "--pattern", "Islet.dmg", "--dir", work.path])
        guard dl.status == 0 else { throw UpdateError(message: "Download failed: \(dl.text)") }

        let mount = work.appendingPathComponent("mnt")
        let attach = await run("/usr/bin/hdiutil", ["attach", work.appendingPathComponent("Islet.dmg").path,
                                                    "-nobrowse", "-readonly", "-mountpoint", mount.path])
        guard attach.status == 0 else { throw UpdateError(message: "Couldn't open the download.") }
        let staged = work.appendingPathComponent("Islet.app")
        let copy = await run("/usr/bin/ditto", [mount.appendingPathComponent("Islet.app").path, staged.path])
        _ = await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        guard copy.status == 0 else { throw UpdateError(message: "Couldn't unpack the update.") }

        let verify = await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        guard verify.status == 0 else { throw UpdateError(message: "The update's signature is invalid, so it was not installed.") }

        // After this process exits: swap the app and reopen it.
        let script = work.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(dest)" && /usr/bin/ditto "\(staged.path)" "\(dest)" && open "\(dest)"
        rm -rf "\(work.path)"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path]
        try p.run()
    }

    nonisolated private static func run(_ path: String, _ args: [String]) async -> (status: Int32, text: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process(), pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch { cont.resume(returning: (-1, error.localizedDescription)); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: (p.terminationStatus, text))
            }
        }
    }

    /// "v1.2" is newer than "1.1"; compares dotted numbers.
    nonisolated static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
