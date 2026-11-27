import CoreWLAN
import Foundation
import SwiftUI

/// A speed test run with macOS's own `networkQuality` tool (no account, no third party). It touches the network only
/// when the user presses Run speed test in the Wi-Fi panel. It runs download then upload (`-s`) under a pseudo-terminal
/// (`script`), because the tool only prints its running figures to a terminal; those become `live`, and the summary
/// it prints at the end becomes the result.
@MainActor @Observable
final class SpeedTest {
    static let shared = SpeedTest()

    /// The tool and its arguments; tests point it at something harmless.
    @ObservationIgnored private let tool: String
    @ObservationIgnored private let toolArguments: [String]?
    init(tool: String = "/usr/bin/networkQuality", arguments: [String]? = nil) { self.tool = tool; toolArguments = arguments }

    struct Result: Equatable {
        /// Megabits per second.
        var download: Double
        var upload: Double
        /// Idle round-trip time in milliseconds.
        var latency: Double
    }

    enum State: Equatable { case idle, running, done(Result), failed(String) }

    /// One redraw of the tool's running line: throughput in Mbps and responsiveness in round trips a minute (RPM),
    /// for the download and the upload.
    struct Figures: Equatable {
        var download: Double
        var downloadRPM: Double
        var upload: Double
        var uploadRPM: Double
    }

    /// The figures so far while a test runs: download, then upload (Mbps), and when each phase began.
    struct Live: Equatable {
        var download: Double = 0
        var upload: Double = 0
        /// The ping right now, in ms: the round trip while the link is loaded (60,000 / the phase's RPM), so higher
        /// than the idle latency the result reports. nil until the tool has measured one.
        var ping: Double?
        var uploading = false
        var since = Date()
    }

    private(set) var state = State.idle {
        didSet { if state != oldValue { live = state == .running ? Live() : nil; show() } }
    }
    private(set) var live: Live?
    private func show() { Self.showInIsland?(Self.progress(state, live: live)) }
    /// The notch's compact state while the panel is closed (nil takes it away). Set by the app delegate.
    static var showInIsland: ((ConnectionProgress?) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var timedOut = false
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    /// Longest a run may take before it is stopped. `-M 24` bounds the test itself, not a stalled start (captive portal, DNS).
    private static let limit: Double = 40
    /// About how long each phase takes, for the notch's bar (it fills half per phase, and jumps to the end when done).
    static let phaseSeconds: Double = 10

    var running: Bool { state == .running }

    static func mbps(_ v: Double) -> String { mbpsNumber(v) + " Mbps" }
    /// "71.9", or "212" from 100 up.
    static func mbpsNumber(_ v: Double) -> String { v >= 100 ? "\(Int(v.rounded()))" : String(format: "%.1f", v) }
    static func summary(_ r: Result) -> String { "↓ \(mbps(r.download))  ↑ \(mbps(r.upload))  \(Int(r.latency.rounded())) ms" }

    /// What the notch says while it runs: the download climbing, then the upload beside the final download.
    static func liveText(_ l: Live?) -> String {
        guard let l, l.download > 0 else { return "Testing speed…" }
        let speeds = l.uploading ? "↓ \(mbps(l.download))  ↑ \(l.upload > 0 ? mbps(l.upload) : "…")" : "↓ \(mbps(l.download))"
        return l.ping.map { "\(speeds)  \(Int($0.rounded())) ms" } ?? speeds
    }

    private static func progress(_ s: State, live: Live?) -> ConnectionProgress? {
        let tint = Color(hex: 0x0A84FF)
        switch s {
        case .idle: return nil
        case .running:
            let l = live ?? Live()
            return ConnectionProgress(name: "Speed test", hotspot: false, state: .working(liveText(l)), icon: "speedometer",
                                      tint: l.uploading ? .speedUpload : .speedDownload,
                                      speed: SpeedPhase(uploading: l.uploading, since: l.since, download: l.download,
                                                        upload: l.upload, ping: l.ping))
        case .done(let r):
            return ConnectionProgress(name: "Speed test", hotspot: false, state: .done, icon: "speedometer", tint: .isletGreen,
                                      doneText: summary(r), hold: 5)
        case .failed(let e):
            return ConnectionProgress(name: "Speed test", hotspot: false, state: .failed(e), icon: "speedometer", tint: tint)
        }
    }

    func run() {
        guard !running else { return }
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            state = .failed("Speed test needs macOS 12 or later."); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: toolArguments == nil ? "/usr/bin/script" : tool)
        p.arguments = toolArguments ?? Self.arguments()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        // Launched here, not later on another thread, so Stop always has a running process to end.
        do { try p.run() } catch { state = .failed("Couldn't run the speed test."); return }
        state = .running
        process = p; cancelled = false; timedOut = false
        observeEnds()
        let handle = out.fileHandleForReading
        nonisolated(unsafe) let proc = p
        // A plain thread reads it: the wait would otherwise hold one of Swift concurrency's few threads for the whole test.
        // It reads as it comes, passing the running figures on at most 5 times a second.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var data = Data()
            var sent = Date.distantPast
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                data.append(chunk)
                guard Date().timeIntervalSince(sent) > 0.2,
                      let figures = Self.parseLive(String(decoding: chunk, as: UTF8.self)) else { continue }
                sent = Date()
                Task { @MainActor in self.update(proc, figures) }
            }
            proc.waitUntilExit()
            Task { @MainActor in self.finish(proc, data) }
        }
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.limit))
            guard !Task.isCancelled, let self, self.process === p, p.isRunning else { return }
            self.timedOut = true
            p.terminate()
        }
    }

    /// While a test runs, the Mac locking, sleeping or the app quitting ends it. (Closing the panel does not.)
    @ObservationIgnored private var endObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private func observeEnds() {
        guard endObservers.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        for (center, name) in [(ws, NSWorkspace.willSleepNotification), (NotificationCenter.default, NSApplication.willTerminateNotification)] {
            endObservers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }))
        }
        let dist = DistributedNotificationCenter.default()
        endObservers.append((dist, dist.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }))
    }

    func cancel() {
        guard let p = process, p.isRunning else { return }
        cancelled = true
        p.terminate()
    }

    /// Stops a running test and forgets the last result (leaving the Wi-Fi page, another network): a result belongs to
    /// the network it was measured on.
    func reset() {
        if running { cancel() } else if state != .idle { state = .idle }
    }

    /// `script` gives networkQuality a terminal, so it prints its figures as it goes. `-s`: download, then upload
    /// (one at a time, so each has its own figure and colour). `-I <interface>`: measure the Wi-Fi link the panel is
    /// about, not whatever route is the default.
    private static func arguments() -> [String] {
        var a = ["-q", "/dev/null", "/usr/bin/networkQuality", "-s", "-M", "24"]
        if let name = CWWiFiClient.shared().interface()?.interfaceName { a += ["-I", name] }
        return a
    }

    private func update(_ p: Process, _ figures: Figures) {
        guard process === p, state == .running, var l = live else { return }
        if !l.uploading && figures.upload > 0 { l.uploading = true; l.since = Date() }
        l.download = figures.download
        l.upload = figures.upload
        let rpm = l.uploading ? figures.uploadRPM : figures.downloadRPM
        if rpm > 0 { l.ping = 60_000 / rpm } // the upload's first readings have none yet: the download's stays
        guard l != live else { return }
        live = l
        show()
    }

    private func finish(_ p: Process, _ data: Data) {
        guard process === p else { return }
        process = nil
        watchdog?.cancel(); watchdog = nil
        endObservers.forEach { $0.0.removeObserver($0.1) }; endObservers = []
        if cancelled { state = .idle; return }
        if timedOut { state = .failed("The speed test timed out."); return }
        state = Self.parseSummary(String(decoding: data, as: UTF8.self))
    }

    /// The newest "Downlink: 71.2 Mbps, 186 RPM - Uplink: 0.000 Mbps, 0 RPM" in what the tool printed (it redraws
    /// one line with carriage returns).
    nonisolated static func parseLive(_ text: String) -> Figures? {
        for line in text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).reversed() {
            // Only a whole line (a read can end mid-number).
            guard line.hasSuffix("RPM") else { continue }
            if let d = number(after: "Downlink: ", in: line), let u = number(after: "Uplink: ", in: line),
               let dr = number(after: " Mbps, ", in: line.prefix { $0 != "-" }), let ur = number(after: " Mbps, ", in: line) {
                return Figures(download: d, downloadRPM: dr, upload: u, uploadRPM: ur)
            }
        }
        return nil
    }

    /// The summary the tool ends with: "Uplink capacity: 16.162 Mbps", "Downlink capacity: 211.804 Mbps",
    /// "Idle Latency: 66.557 milliseconds | 901 RPM".
    nonisolated static func parseSummary(_ text: String) -> State {
        guard let dl = number(after: "Downlink capacity: ", in: Substring(text)),
              let ul = number(after: "Uplink capacity: ", in: Substring(text)) else {
            if text.localizedCaseInsensitiveContains("error") || text.isEmpty { return .failed("No connection, or the test was blocked.") }
            return .failed("Couldn't run the speed test.")
        }
        let rtt = number(after: "Idle Latency: ", in: Substring(text)) ?? 0
        return .done(Result(download: dl, upload: ul, latency: rtt))
    }

    private nonisolated static func number(after label: String, in text: Substring) -> Double? {
        guard let r = text.range(of: label, options: .backwards) else { return nil }
        return Double(text[r.upperBound...].prefix { $0.isNumber || $0 == "." })
    }
}
