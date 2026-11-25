import CoreWLAN
import Foundation

/// A speed test run with macOS's own `networkQuality` tool (no account, no third party). It touches the network only
/// when the user presses Run speed test in the Wi-Fi panel.
@MainActor @Observable
final class SpeedTest {
    static let shared = SpeedTest()

    struct Result: Equatable {
        /// Megabits per second.
        var download: Double
        var upload: Double
        /// Idle round-trip time in milliseconds.
        var latency: Double
    }

    enum State: Equatable { case idle, running, done(Result), failed(String) }

    private(set) var state = State.idle
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var timedOut = false
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    /// Longest a run may take before it is stopped. `-M 15` bounds the test itself, not a stalled start (captive portal, DNS).
    private static let limit: Double = 30

    var running: Bool { state == .running }

    func run() {
        guard !running else { return }
        let tool = "/usr/bin/networkQuality"
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            state = .failed("Speed test needs macOS 12 or later."); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["-c", "-M", "15"] + Self.interfaceArguments()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        // Launched here, not later on another thread, so Stop always has a running process to end.
        do { try p.run() } catch { state = .failed("Couldn't run the speed test."); return }
        state = .running
        process = p; cancelled = false; timedOut = false
        let handle = out.fileHandleForReading
        nonisolated(unsafe) let proc = p
        // A plain thread reads it: the wait would otherwise hold one of Swift concurrency's few threads for the whole test.
        DispatchQueue.global(qos: .userInitiated).async {
            let data = handle.readDataToEndOfFile()
            proc.waitUntilExit()
            Task { @MainActor in SpeedTest.shared.finish(proc, data) }
        }
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.limit))
            guard !Task.isCancelled, let self, self.process === p, p.isRunning else { return }
            self.timedOut = true
            p.terminate()
        }
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

    /// `-I <interface>`: measure the Wi-Fi link the panel is about, not whatever route is the default.
    private static func interfaceArguments() -> [String] {
        guard let name = CWWiFiClient.shared().interface()?.interfaceName else { return [] }
        return ["-I", name]
    }

    private func finish(_ p: Process, _ data: Data) {
        guard process === p else { return }
        process = nil
        watchdog?.cancel(); watchdog = nil
        if cancelled { state = .idle; return }
        if timedOut { state = .failed("The speed test timed out."); return }
        state = Self.parse(data)
    }

    /// The `networkQuality -c` JSON: throughput in bits per second, `base_rtt` in milliseconds.
    nonisolated static func parse(_ data: Data) -> State {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("Couldn't run the speed test.")
        }
        if let message = json["error_code"] as? String, json["dl_throughput"] == nil {
            return .failed("Speed test failed (\(message)).")
        }
        guard let dl = (json["dl_throughput"] as? NSNumber)?.doubleValue,
              let ul = (json["ul_throughput"] as? NSNumber)?.doubleValue else {
            return .failed("No connection, or the test was blocked.")
        }
        let rtt = (json["base_rtt"] as? NSNumber)?.doubleValue ?? 0
        return .done(Result(download: dl / 1_000_000, upload: ul / 1_000_000, latency: rtt))
    }
}
