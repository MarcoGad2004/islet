import AppKit
import ImageIO

/// Now playing for any app, through the vendored mediaremote-adapter (BSD-3): Apple's own /usr/bin/perl is
/// allowed to use MediaRemote, and it loads our helper framework that prints updates as JSON lines.
/// Private-API workaround: a future macOS update could break it. See docs/RESEARCH.md item 7.
@MainActor @Observable
final class MediaMonitor {
    private(set) var info: MediaInfo?
    private(set) var available = true
    /// A browser's website for the track playing (see BrowserSite); nil when it isn't known.
    private(set) var site: String?

    @ObservationIgnored var onChange: ((MediaInfo?) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var state: [String: Any] = [:]
    @ObservationIgnored private var artworkKey = ""
    @ObservationIgnored private var artwork: NSImage?
    /// Where the last seek put the playhead, for a couple of seconds. Browsers (Zen, Chrome...) report the new position
    /// late or not at all, so until the stream agrees the page shows and builds on this, which keeps repeated skips adding up.
    @ObservationIgnored private var siteCache: [String: String] = [:]
    @ObservationIgnored private var siteTask: Task<Void, Never>?
    @ObservationIgnored private var seekHold: (position: Double, at: Date, until: Date)?

    private var resources: (script: String, framework: String)? {
        guard let dir = Bundle.main.resourceURL else { return nil }
        let script = dir.appendingPathComponent("mediaremote-adapter.pl").path
        let fw = dir.appendingPathComponent("MediaRemoteAdapter.framework").path
        return FileManager.default.fileExists(atPath: script) ? (script, fw) : nil
    }

    func start() {
        guard let r = resources else { available = false; return }
        // A previous run that was killed can leave its adapter behind: clear stale ones first.
        let stale = Process()
        stale.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        stale.arguments = ["-f", "mediaremote-adapter.pl .* stream"]
        try? stale.run(); stale.waitUntilExit()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [r.script, r.framework, "stream"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            Task { @MainActor in self?.consume(data) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in if proc.terminationStatus != 0 { self?.available = false } }
        }
        do { try p.run(); process = p } catch { available = false }
    }

    func stop() { process?.terminate(); process = nil }

    // MARK: Parsing

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any] else { continue }
            if (obj["diff"] as? Bool) == true {
                for (k, v) in payload { if v is NSNull { state.removeValue(forKey: k) } else { state[k] = v } }
            } else {
                state = payload
            }
            publish()
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private func publish() {
        guard let bundle = state["bundleIdentifier"] as? String, let title = state["title"] as? String, !title.isEmpty else {
            update(nil); return
        }
        let key = "\(bundle)|\(title)|\(state["album"] as? String ?? "")"
        if key != artworkKey {
            artworkKey = key
            artwork = nil
            site = siteCache[key]
        }
        if artwork == nil, let b64 = state["artworkData"] as? String, let d = Data(base64Encoded: b64) { artwork = Self.downsampled(d) }
        // The encoded copy can be megabytes; the decoded cover is all that's used from here.
        state.removeValue(forKey: "artworkData")
        let ts = (state["timestamp"] as? String).flatMap { Self.iso.date(from: $0) ?? Self.isoPlain.date(from: $0) } ?? Date()
        var m = MediaInfo(bundleID: bundle, title: title, artist: state["artist"] as? String ?? "",
                          album: state["album"] as? String ?? "", playing: state["playing"] as? Bool ?? false,
                          duration: (state["duration"] as? Double) ?? 0, elapsed: (state["elapsedTime"] as? Double) ?? 0,
                          timestamp: ts, rate: (state["playbackRate"] as? Double) ?? 1, artwork: artwork,
                          shuffle: ((state["shuffleMode"] as? Int) ?? 1) > 1, repeatMode: (state["repeatMode"] as? Int) ?? 1)
        if let h = seekHold {
            let now = Date()
            let expected = h.position + (m.playing ? now.timeIntervalSince(h.at) * max(m.rate, 1) : 0)
            if now < h.until, m.title == info?.title, abs(m.position(at: now) - expected) > 1.5 {
                m.elapsed = expected; m.timestamp = now // the player hasn't caught up with the seek yet
            } else { seekHold = nil }
        }
        update(m)
    }

    /// The cover at up to 512 px (it is drawn at 22-80 pt): Apple Music's originals decode to tens of megabytes.
    private static func downsampled(_ data: Data) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return NSImage(data: data) }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 512]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return NSImage(data: data) }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func update(_ new: MediaInfo?) {
        info = new
        onChange?(new) // the store decides how long a paused item keeps the notch (30 s)
    }

    // MARK: Commands

    func togglePlayPause() { run(["send", "2"]) }
    func next() { run(["send", "4"]) }
    func previous() { run(["send", "5"]) }
    func seek(to seconds: Double) {
        run(["seek", String(Int(seconds * 1_000_000))])
        let now = Date()
        seekHold = (seconds, now, now.addingTimeInterval(2))
        info?.elapsed = seconds; info?.timestamp = now; onChange?(info)
    }
    /// Forward or back by seconds. A seek, like the scrubber's, because players answer it more often than they do the
    /// skip-15 commands.
    func skip(seconds: Double) {
        guard let m = info else { return }
        let target = m.position() + seconds
        seek(to: m.duration > 0 ? min(max(target, 0), m.duration) : max(target, 0))
    }

    /// Shuffle on (tracks) or off. The button shows the new state at once; the player's own update confirms it.
    func setShuffle(_ on: Bool) {
        run(["shuffle", on ? "3" : "1"])
        info?.shuffle = on; onChange?(info)
    }

    /// Repeat: off, then all, then one track, then off again.
    func cycleRepeat() {
        let next = [1: 3, 3: 2, 2: 1][info?.repeatMode ?? 1] ?? 3
        run(["repeat", String(next)])
        info?.repeatMode = next; onChange?(info)
    }

    /// Looks up the website for a browser's track (cached per track). Called when the Now Playing page shows.
    func refreshSite() {
        guard let m = info, m.isBrowser else { site = nil; return }
        let key = "\(m.bundleID)|\(m.title)"
        if let cached = siteCache[key] { site = cached; return }
        siteTask?.cancel()
        siteTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { BrowserSite.find(bundleID: m.bundleID, mediaTitle: m.title) }.value
            guard !Task.isCancelled, let self, let found, self.info?.title == m.title else { return }
            if self.siteCache.count > 40 { self.siteCache.removeAll() }
            self.siteCache[key] = found
            self.site = found
        }
    }

    func activatePlayer() {
        guard let id = info?.bundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate()
    }

    private func run(_ args: [String]) {
        guard let r = resources else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [r.script, r.framework] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
