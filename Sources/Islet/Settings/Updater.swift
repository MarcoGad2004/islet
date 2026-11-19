import SwiftUI

/// Updates Islet from the newest GitHub release of this repo. Only runs when the user clicks "Check for updates".
/// The repo is public, so it reads GitHub's public releases API directly: no account, no token, no GitHub CLI.
/// The release carries `Islet.dmg`; the new app replaces this one after Islet quits, and only when it is signed by
/// the same developer as the running copy.
///
/// The island follows along: each step shows as it happens, the island draws back in before Islet quits, and the new
/// copy says "Updated to …" when it opens, with What's new a click away (`announceIfJustUpdated`).
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
    /// Release notes of the release found by `check()` (Markdown from CHANGELOG.md).
    private(set) var notes = ""
    /// The DMG of the release found by `check()`.
    @ObservationIgnored private var dmgURL: URL?
    @ObservationIgnored private var shownPercent = -1

    /// Shows a step in the island, and takes it away. Set by the app delegate.
    static var showInIsland: ((ConnectionProgress, (() -> Void)?) -> Void)?
    static var clearIsland: (() -> Void)?

    var currentVersion: String { Self.currentVersion }
    nonisolated static var currentVersion: String {
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
                notes = latest.notes
                state = Self.isNewer(latest.tag, than: currentVersion) ? .available(latest.tag) : .upToDate
            } catch {
                state = .failed((error as? UpdateError)?.message ?? "Couldn't reach GitHub: \(error.localizedDescription)")
            }
        }
    }

    func showNotes(_ tag: String) { ReleaseNotesWindow.show(version: Self.plain(tag), notes: notes) }

    func install(_ tag: String) {
        guard installable else {
            state = .failed("Move Islet to the Applications folder to update it in place.")
            return
        }
        guard let dmg = dmgURL else { state = .failed("The release has no Islet.dmg."); return }
        let version = Self.plain(tag)
        state = .downloading(tag)
        Task {
            do {
                island(.working("Downloading \(version)…"))
                shownPercent = -1
                let file = try await Self.download(dmg) { fraction in
                    Task { @MainActor in
                        // Whole percents only, so the text doesn't churn.
                        let pct = Int(fraction * 100)
                        guard pct != self.shownPercent, case .downloading = self.state else { return }
                        self.shownPercent = pct
                        self.island(.working("Downloading \(version) · \(pct)%"))
                    }
                }
                island(.working("Checking the update…"))
                let staged = try await Self.unpackAndVerify(file, against: Bundle.main.bundlePath)
                island(.working("Installing \(version)…"))
                try Self.scheduleSwap(staged, dest: Bundle.main.bundlePath)
                // The new copy reads this when it opens and says how it went.
                Self.pending = Pending(from: currentVersion, to: version, notes: notes)
                island(.working("Restarting Islet…"))
                try? await Task.sleep(for: .seconds(1.2))
                // Let the island draw back into the notch, then quit; the swap script reopens Islet.
                Self.clearIsland?()
                try? await Task.sleep(for: .seconds(0.7))
                NSApp.terminate(nil)
            } catch {
                let message = (error as? UpdateError)?.message ?? error.localizedDescription
                state = .failed(message)
                island(.failed("Update failed"), hold: 4)
            }
        }
    }

    private func island(_ s: ConnectionProgress.State, hold: Double? = nil) {
        Self.showInIsland?(Self.progress(s, hold: hold), nil)
    }

    private static func progress(_ s: ConnectionProgress.State, done: String? = nil, action: String? = nil, hold: Double? = nil) -> ConnectionProgress {
        let finished = s == .done
        return ConnectionProgress(name: "Islet", hotspot: false, state: s, icon: finished ? "checkmark.circle.fill" : "arrow.down.circle.fill",
                           tint: finished ? Color.isletGreen : Color(hex: 0x0A84FF),
                           doneText: done, actionLabel: action, hold: hold)
    }

    // MARK: After the relaunch

    struct Pending: Codable { var from: String; var to: String; var notes: String }
    private static let pendingKey = "IsletPendingUpdate"

    static var pending: Pending? {
        get { UserDefaults.standard.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: pendingKey) }
    }

    /// Called once at launch: if Islet just updated itself, the island says so (or that it didn't work), with the
    /// release notes a click away.
    static func announceIfJustUpdated() {
        guard let p = pending else { return }
        pending = nil
        Task { @MainActor in
            // Let the island settle after launch, so it grows out of the notch on its own.
            try? await Task.sleep(for: .seconds(1.5))
            if !isNewer(p.to, than: currentVersion) {
                let notes = p.notes
                showInIsland?(progress(.done, done: "Updated to \(currentVersion)", action: notes.isEmpty ? nil : "What's new", hold: 8),
                              notes.isEmpty ? nil : { ReleaseNotesWindow.show(version: p.to, notes: notes) })
            } else {
                showInIsland?(progress(.failed("Update to \(p.to) didn't install"), hold: 6), nil)
            }
        }
    }

    // MARK: - Work off the main actor

    struct UpdateError: Error { let message: String }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let assets: [Asset]
    }

    nonisolated private static func latestRelease() async throws -> (tag: String, dmg: URL?, notes: String) {
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
        return (r.tag_name, r.assets.first { $0.name == "Islet.dmg" }?.browser_download_url, r.body ?? "")
    }

    /// Downloads into a fresh folder, reporting 0...1 as it goes.
    nonisolated private static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("islet-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let dest = work.appendingPathComponent("Islet.dmg")
        return try await withCheckedThrowingContinuation { cont in
            let box = ObservationBox()
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                box.observation?.invalidate()
                if let error { cont.resume(throwing: UpdateError(message: "Download failed: \(error.localizedDescription)")); return }
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    cont.resume(throwing: UpdateError(message: "Download failed.")); return
                }
                do { try FileManager.default.moveItem(at: tmp, to: dest); cont.resume(returning: dest) }
                catch { cont.resume(throwing: UpdateError(message: "Download failed: \(error.localizedDescription)")) }
            }
            box.observation = task.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            task.resume()
        }
    }

    private final class ObservationBox: @unchecked Sendable { var observation: NSKeyValueObservation? }

    /// Opens the DMG, copies the app out and checks it is intact and from the same developer as `current`.
    nonisolated private static func unpackAndVerify(_ dmg: URL, against current: String) async throws -> URL {
        let work = dmg.deletingLastPathComponent()
        let mount = work.appendingPathComponent("mnt")
        let attach = await run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        guard attach.status == 0 else { throw UpdateError(message: "Couldn't open the download.") }
        let staged = work.appendingPathComponent("Islet.app")
        let copy = await run("/usr/bin/ditto", [mount.appendingPathComponent("Islet.app").path, staged.path])
        _ = await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        guard copy.status == 0 else { throw UpdateError(message: "Couldn't unpack the update.") }

        let verify = await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        guard verify.status == 0 else { throw UpdateError(message: "The update's signature is invalid, so it was not installed.") }
        // Downloaded without a browser, the update gets no Gatekeeper check, so it must come from the same developer
        // as the copy that is running (when that copy is signed by one).
        if let mine = await teamID(current) {
            guard await teamID(staged.path) == mine else {
                throw UpdateError(message: "The update isn't signed by the same developer, so it was not installed.")
            }
        }
        return staged
    }

    /// After this process exits: swap the app and reopen it.
    nonisolated private static func scheduleSwap(_ staged: URL, dest: String) throws {
        let work = staged.deletingLastPathComponent()
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

    /// "v1.2.2" → "1.2.2".
    nonisolated static func plain(_ tag: String) -> String { tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }

    /// "v1.2" is newer than "1.1"; compares dotted numbers.
    nonisolated static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] { plain(s).split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
