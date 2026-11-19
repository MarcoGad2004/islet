import AppKit

/// Updates Islet from the newest GitHub release of this repo. Only runs when the user clicks "Check for updates".
/// The repo is public, so it reads GitHub's public releases API directly: no account, no token, no GitHub CLI.
/// The release carries `Islet.dmg`; the new app replaces this one after Islet quits, and only when it is signed by
/// the same developer as the running copy.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(String)
        case downloading(String)
        case failed(String)
    }

    nonisolated static let repo = "MarcoGad2004/islet"
    private(set) var state = State.idle
    /// The DMG of the release found by `check()`.
    @ObservationIgnored private var dmgURL: URL?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Installing replaces the running app, so it only makes sense for a copy in Applications.
    private var installable: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Applications/") || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func check() {
        state = .checking
        Task {
            do {
                let latest = try await Self.latestRelease()
                dmgURL = latest.dmg
                state = Self.isNewer(latest.tag, than: currentVersion) ? .available(latest.tag) : .upToDate
            } catch {
                state = .failed((error as? UpdateError)?.message ?? "Couldn't reach GitHub: \(error.localizedDescription)")
            }
        }
    }

    func install(_ tag: String) {
        guard installable else {
            state = .failed("Move Islet to the Applications folder to update it in place.")
            return
        }
        guard let dmg = dmgURL else { state = .failed("The release has no Islet.dmg."); return }
        state = .downloading(tag)
        Task {
            do { try await Self.install(dmg: dmg, dest: Bundle.main.bundlePath) }
            catch { state = .failed((error as? UpdateError)?.message ?? error.localizedDescription); return }
            NSApp.terminate(nil)
        }
    }

    // MARK: - Work off the main actor

    struct UpdateError: Error { let message: String }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let assets: [Asset]
    }

    nonisolated private static func latestRelease() async throws -> (tag: String, dmg: URL?) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Islet-updater", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 404: throw UpdateError(message: "No release found on GitHub.")
        case 403, 429: throw UpdateError(message: "GitHub is limiting requests right now; try again in a while.")
        default: throw UpdateError(message: "Couldn't reach GitHub (HTTP \(status)).")
        }
        let r = try JSONDecoder().decode(Release.self, from: data)
        return (r.tag_name, r.assets.first { $0.name == "Islet.dmg" }?.browser_download_url)
    }

    nonisolated private static func install(dmg: URL, dest: String) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("islet-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let file = work.appendingPathComponent("Islet.dmg")
        do {
            let (tmp, response) = try await URLSession.shared.download(from: dmg)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(message: "Download failed.") }
            try fm.moveItem(at: tmp, to: file)
        } catch let e as UpdateError { throw e } catch { throw UpdateError(message: "Download failed: \(error.localizedDescription)") }

        let mount = work.appendingPathComponent("mnt")
        let attach = await run("/usr/bin/hdiutil", ["attach", file.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        guard attach.status == 0 else { throw UpdateError(message: "Couldn't open the download.") }
        let staged = work.appendingPathComponent("Islet.app")
        let copy = await run("/usr/bin/ditto", [mount.appendingPathComponent("Islet.app").path, staged.path])
        _ = await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        guard copy.status == 0 else { throw UpdateError(message: "Couldn't unpack the update.") }

        let verify = await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        guard verify.status == 0 else { throw UpdateError(message: "The update's signature is invalid, so it was not installed.") }
        // Downloaded without a browser, the update gets no Gatekeeper check, so it must come from the same developer
        // as the copy that is running (when that copy is signed by one).
        if let mine = await teamID(dest) {
            guard await teamID(staged.path) == mine else {
                throw UpdateError(message: "The update isn't signed by the same developer, so it was not installed.")
            }
        }

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

    /// The signing team of an app, or nil when it has none (ad-hoc or unsigned).
    nonisolated private static func teamID(_ app: String) async -> String? {
        let out = await run("/usr/bin/codesign", ["-dv", app])
        let line = out.text.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }
        let id = line.map { String($0.dropFirst("TeamIdentifier=".count)) }
        return id == nil || id == "not set" ? nil : id
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
