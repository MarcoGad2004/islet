import AppKit

/// Now playing for any app, through the vendored mediaremote-adapter (BSD-3): Apple's own /usr/bin/perl is
/// allowed to use MediaRemote, and it loads our helper framework that prints updates as JSON lines.
/// Private-API workaround: a future macOS update could break it. See docs/RESEARCH.md item 7.
@MainActor @Observable
final class MediaMonitor {
    private(set) var info: MediaInfo?
    private(set) var available = true

    @ObservationIgnored var onChange: ((MediaInfo?) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var state: [String: Any] = [:]
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var artworkKey = ""
    @ObservationIgnored private var artwork: NSImage?

    private var resources: (script: String, framework: String)? {
        guard let dir = Bundle.main.resourceURL else { return nil }
        let script = dir.appendingPathComponent("mediaremote-adapter.pl").path
        let fw = dir.appendingPathComponent("MediaRemoteAdapter.framework").path
        return FileManager.default.fileExists(atPath: script) ? (script, fw) : nil
    }

    func start() {
        guard let r = resources else { available = false; return }
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
        }
        if artwork == nil, let b64 = state["artworkData"] as? String, let d = Data(base64Encoded: b64) { artwork = NSImage(data: d) }
        let ts = (state["timestamp"] as? String).flatMap { Self.iso.date(from: $0) ?? Self.isoPlain.date(from: $0) } ?? Date()
        let m = MediaInfo(bundleID: bundle, title: title, artist: state["artist"] as? String ?? "",
                          album: state["album"] as? String ?? "", playing: state["playing"] as? Bool ?? false,
                          duration: (state["duration"] as? Double) ?? 0, elapsed: (state["elapsedTime"] as? Double) ?? 0,
                          timestamp: ts, rate: (state["playbackRate"] as? Double) ?? 1, artwork: artwork)
        update(m)
    }

    private func update(_ new: MediaInfo?) {
        hideTask?.cancel()
        info = new
        guard let new else { onChange?(nil); return }
        onChange?(new)
        if !new.playing {
            // Hide 30 s after pause.
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.onChange?(nil)
            }
        }
    }

    // MARK: Commands

    func togglePlayPause() { run(["send", "2"]) }
    func next() { run(["send", "4"]) }
    func previous() { run(["send", "5"]) }
    func seek(to seconds: Double) { run(["seek", String(Int(seconds * 1_000_000))]) }

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
