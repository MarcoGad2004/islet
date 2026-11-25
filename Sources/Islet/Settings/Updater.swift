import SwiftUI

/// Updates Islet from the newest GitHub release of this repo. Only runs when the user clicks "Check for updates".
/// The repo is public, so it reads GitHub's public releases API directly: no account, no token, no GitHub CLI.
/// The release carries `Dynamic Peninsula.dmg` (and `Islet.dmg` for copies from before the 1.5 rename); the new app replaces this one after Islet quits, and only when it is signed by
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
    /// Release notes of everything newer than the running version up to the release found by `check()` (Markdown from
    /// CHANGELOG.md; one section per version, newest first, when an update skips versions).
    private(set) var notes = ""
    /// The DMG of the release found by `check()`.
    @ObservationIgnored private var dmgURL: URL?
    @ObservationIgnored private var shownPercent = -1
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    /// Shows a step in the island, and takes it away. Set by the app delegate.
    static var showInIsland: ((ConnectionProgress, (() -> Void)?) -> Void)?
    static var clearIsland: (() -> Void)?
    static var revealIsland: (() -> Void)?
    /// Whether the island is using the wide bar right now (rather than the chin).
    static var islandIsWide: (() -> Bool)?
    /// Stop and restart what must not run in two copies at once (the key tap, the media helper).
    static var pauseForHandoff: (() -> Void)?
    static var resumeAfterHandoff: (() -> Void)?

    var currentVersion: String { Self.currentVersion }
    nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Installing replaces the running app, so it only makes sense for a copy in Applications.
    private var installable: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Applications/") || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// The one updater: Settings, the panel's update pill and the automatic checks share it.
    static let shared = Updater()

    /// Settings → Updates → "Check for updates automatically" (on unless turned off).
    static let autoCheckKey = "checkUpdatesAutomatically"
    /// Automatic checks: once a minute after launch, then whenever 6 hours have passed since the last one.
    nonisolated static let autoCheckInterval: TimeInterval = 6 * 60 * 60
    private static let lastCheckKey = "IsletLastUpdateCheck"
    @ObservationIgnored private var autoTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    private init() {
        UserDefaults.standard.register(defaults: [Self.autoCheckKey: true])
    }

    /// A tag the user can install now: what the panel's update pill offers.
    var availableTag: String? { if case .available(let t) = state { t } else { nil } }

    /// `silent` is an automatic check: a failure leaves things as they were instead of showing an error in Settings,
    /// and an update already on offer stays on offer while it looks again.
    func check(silent: Bool = false) {
        if case .downloading = state { return }
        if silent, checkTask != nil { return }
        checkTask?.cancel()
        let before = state
        if !(silent && availableTag != nil) { state = .checking }
        checkTask = Task {
            defer { if !Task.isCancelled { checkTask = nil } }
            do {
                let latest = try await Self.latestRelease()
                // An install started meanwhile (or a newer check) owns the state now.
                if Task.isCancelled { return }
                if case .downloading = state { return }
                dmgURL = latest.dmg
                notes = Self.combinedNotes(latest.releases, after: currentVersion, upTo: latest.tag)
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                state = Self.isNewer(latest.tag, than: currentVersion) ? .available(latest.tag) : .upToDate
            } catch {
                if Task.isCancelled { return }
                if case .downloading = state { return }
                if silent {
                    if case .checking = state { state = before == .checking ? .idle : before }
                    return
                }
                state = .failed((error as? UpdateError)?.message ?? "Couldn't reach GitHub: \(error.localizedDescription)")
            }
        }
    }

    /// Starts the automatic checks (called once at launch). Each tick only looks at the clock; GitHub is asked only
    /// when a check is due and the setting is on. Waking from sleep looks again soon after, once the network is back.
    func startAutomaticChecks() {
        guard autoTask == nil else { return }
        var first: TimeInterval = 60
        #if DEBUG
        if UserDefaults.standard.string(forKey: "IsletDebugUpdateDMG") != nil { first = 0.5 }
        #endif
        autoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(first))
            self?.autoCheck(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10 * 60))
                self?.autoCheck(force: false)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.autoCheck(force: false)
            }
        }
    }

    private func autoCheck(force: Bool) {
        guard UserDefaults.standard.bool(forKey: Self.autoCheckKey) else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) >= Self.autoCheckInterval else { return }
        check(silent: true)
    }

    func showNotes(_ tag: String) { ReleaseNotesWindow.show(version: Self.plain(tag), notes: notes) }

    func install(_ tag: String) {
        if case .downloading = state { return }
        guard installable else {
            state = .failed("Move Dynamic Peninsula to the Applications folder to update it in place.")
            return
        }
        guard let dmg = dmgURL else { state = .failed("The release has no download for this Mac."); return }
        let version = Self.plain(tag)
        checkTask?.cancel(); checkTask = nil // a check still running must not overwrite the install's state
        state = .downloading(tag)
        Task {
            var work: URL? // the download's folder; goes unless the new copy took over
            do {
                island(.working("Downloading \(version)…"), 0.02)
                shownPercent = -1
                let file = try await Self.download(dmg) { fraction in
                    Task { @MainActor in
                        // Whole percents only, so the text doesn't churn.
                        let pct = Int(fraction * 100)
                        guard pct != self.shownPercent, case .downloading = self.state else { return }
                        self.shownPercent = pct
                        self.island(.working("Downloading \(version) · \(pct)%"), Self.downloadShare * fraction)
                    }
                }
                work = file.deletingLastPathComponent()
                island(.working("Verifying the update…"), 0.78)
                let staged = try await Self.unpackAndVerify(file, against: Bundle.main.bundlePath, tag: tag)
                island(.working("Installing \(version)…"), 0.88)
                try await handOff(to: staged, version: version)
            } catch {
                if let work { try? FileManager.default.removeItem(at: work) }
                let message = (error as? UpdateError)?.message ?? error.localizedDescription
                state = .failed(message)
                island(.failed("Update failed"), lastFraction, hold: 4)
            }
        }
    }

    /// The handoff: the notch never goes blank. This copy keeps drawing while the new one is put in place and
    /// launched; the new one opens in the same "Restarting…" shape, says when it is on screen, and only then does this
    /// copy quit, so the island carries straight on into "Updated to …". If the new copy never checks in, the old app
    /// goes back and stays running.
    private func handOff(to staged: URL, version: String) async throws {
        let current = URL(fileURLWithPath: Bundle.main.bundlePath)
        // Since 1.5 the app is "Dynamic Peninsula.app"; an Islet.app is renamed as it's replaced (unless something
        // else already has that name there).
        let named = current.deletingLastPathComponent().appendingPathComponent(Self.appFile)
        let dest = current == named || FileManager.default.fileExists(atPath: named.path) ? current : named
        // Two copies are briefly up at once: stop the ones that must not run twice (key tap, media helper).
        Self.pauseForHandoff?()
        let backup: URL
        do { backup = try await Self.swapIn(staged, replacing: current, at: dest) }
        catch { Self.resumeAfterHandoff?(); throw error }
        Self.pending = Pending(from: currentVersion, to: version, notes: notes)
        island(.working("Restarting Dynamic Peninsula…"), Self.restartFraction)
        try? await Task.sleep(for: .seconds(0.5))

        let (ready, newCopy) = await Self.launchAndWait(dest)
        if ready {
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            NSApp.terminate(nil)
            return
        }
        // Roll back: close the new copy if it is up, and put this version back where it was.
        newCopy?.forceTerminate()
        try? await Task.sleep(for: .seconds(0.3))
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: backup, to: current)
        Self.pending = nil
        Self.resumeAfterHandoff?()
        throw UpdateError(message: "The new version didn't start, so Dynamic Peninsula put the old one back.")
    }

    /// The download is most of the bar; verifying, installing and restarting fill the rest.
    nonisolated static let downloadShare = 0.7
    nonisolated static let restartFraction = 0.95
    @ObservationIgnored private var lastFraction = 0.0

    private func island(_ s: ConnectionProgress.State, _ fraction: Double, hold: Double? = nil) {
        lastFraction = fraction
        Self.showInIsland?(Self.progress(s, fraction: fraction, hold: hold), nil)
    }

    private static func progress(_ s: ConnectionProgress.State, fraction: Double, done: String? = nil, action: String? = nil,
                                 hold: Double? = nil) -> ConnectionProgress {
        let finished = s == .done
        return ConnectionProgress(name: "Dynamic Peninsula", hotspot: false, state: s, icon: finished ? "sparkles" : "arrow.down.circle.fill",
                           tint: finished ? Color.isletGreen : Color(hex: 0x0A84FF),
                           doneText: done, actionLabel: action, hold: hold, fraction: fraction)
    }

    // MARK: After the relaunch

    struct Pending: Codable { var from: String; var to: String; var notes: String }
    private static let pendingKey = "IsletPendingUpdate"

    static var pending: Pending? {
        get { UserDefaults.standard.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: pendingKey) }
    }

    nonisolated static let handoffReady = Notification.Name("com.marcogad.islet.handoffReady")
    /// Set by the old copy when it launches this one to take over the island.
    private static var launchedForHandoff: Bool { UserDefaults.standard.bool(forKey: "IsletHandoff") }

    /// Called once at launch. Launched by an update, it takes the island over from the old copy (same "Restarting…"
    /// shape, then tells it to quit) and goes on to say "Updated to …", with the release notes a click away.
    static func announceIfJustUpdated() {
        let handoff = launchedForHandoff
        #if DEBUG
        // Testing the rollback: a new copy that never checks in.
        if handoff && UserDefaults.standard.bool(forKey: "IsletDebugNoHandoff") { return }
        #endif
        guard let p = pending else {
            if handoff { revealIsland?(); DistributedNotificationCenter.default().postNotificationName(handoffReady, object: nil, deliverImmediately: true) }
            removeOldCopies()
            return
        }
        pending = nil
        Task { @MainActor in
            if handoff {
                // Draw the same shape the old copy is showing, unseen, until it has fully settled; then show it in one
                // step on top of the old one (identical, so nothing changes on screen) and let the old one go.
                showInIsland?(progress(.working("Restarting Dynamic Peninsula…"), fraction: restartFraction), nil)
                try? await Task.sleep(for: .seconds(1.2))
                revealIsland?()
                DistributedNotificationCenter.default().postNotificationName(handoffReady, object: nil, deliverImmediately: true)
                try? await Task.sleep(for: .seconds(0.6))
            } else {
                // Let the island settle after launch, so it grows out of the notch on its own.
                try? await Task.sleep(for: .seconds(1.5))
            }
            if !isNewer(p.to, than: currentVersion) {
                let notes = p.notes
                showInIsland?(progress(.done, fraction: 1, done: "Updated to \(currentVersion)", action: notes.isEmpty ? nil : "What's new", hold: 8),
                              notes.isEmpty ? nil : { ReleaseNotesWindow.show(version: p.to, notes: notes) })
            } else {
                showInIsland?(progress(.failed("Update to \(p.to) didn't install"), fraction: restartFraction, hold: 6), nil)
            }
            try? await Task.sleep(for: .seconds(3))
            removeOldCopies()
        }
    }

    /// The previous version's app, moved aside during an update (".Islet-old-….app" next to this one).
    private static func removeOldCopies() {
        let dir = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where (name.hasPrefix(".Islet-old-") || name.hasPrefix(".Islet-new-")) && name.hasSuffix(".app") {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Opens the new copy as a second instance and waits up to 15 s for it to say its island is on screen.
    private static func launchAndWait(_ app: URL) async -> (ready: Bool, app: NSRunningApplication?) {
        let waiter = HandoffWaiter() // listening before the launch, so a quick check-in isn't missed
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        // The new copy starts in the same layout (wide bar or chin) as this one, so the two islands match exactly.
        config.arguments = ["-IsletHandoff", "YES", "-IsletHandoffWide", islandIsWide?() == true ? "YES" : "NO"]
        let running = try? await NSWorkspace.shared.openApplication(at: app, configuration: config)
        guard running != nil else { return (false, nil) }
        return (await waiter.wait(seconds: 15), running)
    }

    // MARK: - Work off the main actor

    struct UpdateError: Error { let message: String }

    struct ReleaseInfo: Equatable { let tag: String; let notes: String; let dmg: URL? }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// GitHub turns the spaces in an uploaded file's name into dots ("Dynamic Peninsula.dmg" is served as
    /// "Dynamic.Peninsula.dmg"), so names are compared with spaces and dots treated alike.
    nonisolated private static func assetKey(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: ".")
    }

    /// The download in a release's assets: `Dynamic Peninsula.dmg`, else `Islet.dmg` (for copies from before 1.5).
    nonisolated static func downloadURL(in assets: [(name: String, url: URL)]) -> URL? {
        for wanted in [dmgFile, legacyDmgFile] {
            if let a = assets.first(where: { assetKey($0.name) == assetKey(wanted) }) { return a.url }
        }
        return nil
    }

    /// The release to install: the highest version that has a download, whatever order GitHub lists them in, so an
    /// older or skipped release is never picked and 1.4 goes straight to 1.6 when 1.6 is out. Nil when none has one.
    nonisolated static func newest(of releases: [ReleaseInfo]) -> ReleaseInfo? {
        releases.filter { $0.dmg != nil }.max { isNewer($1.tag, than: $0.tag) }
    }

    /// Notes for every release after `current` up to `latest`, newest first. A single release's notes come back as they
    /// are; several get a version heading each. Versions GitHub doesn't list, or that have no notes, are left out.
    nonisolated static func combinedNotes(_ releases: [ReleaseInfo], after current: String, upTo latest: String) -> String {
        var seen = Set<String>()
        let range = releases
            .filter { isNewer($0.tag, than: current) && !isNewer($0.tag, than: latest) }
            .filter { seen.insert(plain($0.tag)).inserted }
            .sorted { isNewer($0.tag, than: $1.tag) }
            .filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if range.count == 1 { return range[0].notes }
        return range.map { "## \(plain($0.tag))\n\n\($0.notes.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n\n")
    }

    nonisolated private static func latestRelease() async throws -> (tag: String, dmg: URL?, releases: [ReleaseInfo]) {
        #if DEBUG
        // Testing the whole update without GitHub: a local DMG and the version it holds.
        if let dmg = UserDefaults.standard.string(forKey: "IsletDebugUpdateDMG") {
            let v = UserDefaults.standard.string(forKey: "IsletDebugUpdateVersion") ?? "9.9.9"
            let info = ReleaseInfo(tag: "v\(v)", notes: "- A test update, installed from a local DMG.", dmg: URL(fileURLWithPath: dmg))
            return (info.tag, info.dmg, [info])
        }
        #endif
        // The whole list (not /releases/latest, which is the most recently created release, not the highest version).
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=100")!)
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
        let all = try JSONDecoder().decode([Release].self, from: data)
        // Releases since 1.5 carry "Dynamic Peninsula.dmg", and "Islet.dmg" for copies from before the rename.
        let releases = all.filter { $0.draft != true && $0.prerelease != true }.map { r in
            let dmg = downloadURL(in: r.assets.map { ($0.name, $0.browser_download_url) })
            return ReleaseInfo(tag: r.tag_name, notes: r.body ?? "", dmg: dmg)
        }
        let top = newest(of: releases) ?? releases.max { isNewer($1.tag, than: $0.tag) }
        guard let top else { throw UpdateError(message: "No release found on GitHub.") }
        return (top.tag, top.dmg, releases)
    }

    /// Downloads into a fresh folder, reporting 0...1 as it goes.
    nonisolated private static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("islet-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let dest = work.appendingPathComponent(dmgFile)
        return try await withCheckedThrowingContinuation { cont in
            let box = ObservationBox()
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                box.observation?.invalidate()
                func fail(_ message: String) {
                    try? FileManager.default.removeItem(at: work)
                    cont.resume(throwing: UpdateError(message: message))
                }
                if let error { fail("Download failed: \(error.localizedDescription)"); return }
                guard let tmp, url.isFileURL || (response as? HTTPURLResponse)?.statusCode == 200 else {
                    fail("Download failed."); return
                }
                do { try FileManager.default.moveItem(at: tmp, to: dest); cont.resume(returning: dest) }
                catch { fail("Download failed: \(error.localizedDescription)") }
            }
            box.observation = task.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            task.resume()
        }
    }

    private final class ObservationBox: @unchecked Sendable { var observation: NSKeyValueObservation? }

    /// Opens the DMG, copies the app out and checks it is intact and from the same developer as `current`.
    nonisolated private static func unpackAndVerify(_ dmg: URL, against current: String, tag: String) async throws -> URL {
        let work = dmg.deletingLastPathComponent()
        // The release DMGs are signed. Look at that before the image is opened: one signed by another developer is
        // refused (an unsigned one still has to pass the app's own checks below).
        let mine = await teamID(current)
        if let mine, let theirs = await teamID(dmg.path), theirs != mine {
            throw UpdateError(message: "The update isn't signed by the same developer, so it was not installed.")
        }
        let mount = work.appendingPathComponent("mnt")
        let attach = await run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        guard attach.status == 0 else { throw UpdateError(message: "Couldn't open the download.") }
        let staged = work.appendingPathComponent(appFile)
        let inside = [appFile, legacyAppFile].map { mount.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? mount.appendingPathComponent(appFile)
        let copy = await run("/usr/bin/ditto", [inside.path, staged.path])
        _ = await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        guard copy.status == 0 else { throw UpdateError(message: "Couldn't unpack the update.") }

        let verify = await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        guard verify.status == 0 else { throw UpdateError(message: "The update's signature is invalid, so it was not installed.") }
        // Downloaded without a browser, the update gets no Gatekeeper check, so it must come from the same developer
        // as the copy that is running (when that copy is signed by one).
        if let mine {
            guard await teamID(staged.path) == mine else {
                throw UpdateError(message: "The update isn't signed by the same developer, so it was not installed.")
            }
        }
        // It must be this app, at the version the release says (a stale build in the DMG would reinstall itself forever).
        let info = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError(message: "The download isn't Dynamic Peninsula, so it was not installed.")
        }
        var skipVersionCheck = false
        #if DEBUG
        skipVersionCheck = UserDefaults.standard.string(forKey: "IsletDebugUpdateDMG") != nil
        #endif
        if !skipVersionCheck, let v = info?["CFBundleShortVersionString"] as? String, isNewer(tag, than: v) {
            throw UpdateError(message: "The download is older than the release (\(v)), so it was not installed.")
        }
        return staged
    }

    /// Puts the new app where this one is. The new copy is written beside it first, so the app is never missing while
    /// a 130 MB copy runs; then this copy's bundle is renamed aside (not deleted: it keeps running from it and is put
    /// back if the new one never starts) and the new one renamed into place, two renames a moment apart.
    nonisolated private static func swapIn(_ staged: URL, replacing current: URL, at dest: URL) async throws -> URL {
        let fm = FileManager.default
        let dir = current.deletingLastPathComponent()
        let tag = UUID().uuidString.prefix(8)
        let fresh = dir.appendingPathComponent(".Islet-new-\(tag).app")
        let backup = dir.appendingPathComponent(".Islet-old-\(tag).app")
        let copy = await run("/usr/bin/ditto", [staged.path, fresh.path])
        guard copy.status == 0 else {
            try? fm.removeItem(at: fresh)
            throw UpdateError(message: "Couldn't install the update in \(dir.path).")
        }
        do { try fm.moveItem(at: current, to: backup) }
        catch {
            try? fm.removeItem(at: fresh)
            throw UpdateError(message: "Couldn't replace Dynamic Peninsula in \(dir.path).")
        }
        do { try fm.moveItem(at: fresh, to: dest) }
        catch {
            try? fm.removeItem(at: fresh)
            try? fm.moveItem(at: backup, to: current)
            throw UpdateError(message: "Couldn't install the update.")
        }
        return backup
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

    /// The app's file and download names since the 1.5 rename, and the ones before it.
    nonisolated static let appFile = "Dynamic Peninsula.app"
    nonisolated static let legacyAppFile = "Islet.app"
    nonisolated static let dmgFile = "Dynamic Peninsula.dmg"
    nonisolated static let legacyDmgFile = "Islet.dmg"

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

/// Waits for the new copy's "my island is up" during an update's handoff.
@MainActor private final class HandoffWaiter {
    private var ready = false
    private var cont: CheckedContinuation<Bool, Never>?
    private var observer: NSObjectProtocol?

    init() {
        observer = DistributedNotificationCenter.default().addObserver(forName: Updater.handoffReady, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(true) }
        }
    }

    func wait(seconds: Double) async -> Bool {
        defer { if let o = observer { DistributedNotificationCenter.default().removeObserver(o); observer = nil } }
        if ready { return true }
        return await withCheckedContinuation { c in
            cont = c
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.fire(false)
            }
        }
    }

    private func fire(_ ok: Bool) {
        if ok { ready = true }
        guard let c = cont else { return }
        cont = nil
        c.resume(returning: ok)
    }
}
