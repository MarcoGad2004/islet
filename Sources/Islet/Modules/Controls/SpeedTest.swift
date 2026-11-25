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

    var running: Bool { state == .running }

    func run() {
        guard !running else { return }
        let tool = "/usr/bin/networkQuality"
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            state = .failed("Speed test needs macOS 12 or later."); return
        }
        state = .running
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["-c", "-M", "15"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        process = p
        Task.detached {
            var data = Data()
            do {
                try p.run()
                data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
            } catch {
                await MainActor.run { SpeedTest.shared.finish(nil, cancelled: false) }
                return
            }
            let cancelled = p.terminationReason == .uncaughtSignal
            await MainActor.run { SpeedTest.shared.finish(data, cancelled: cancelled) }
        }
    }

    func cancel() {
        process?.terminate()
    }

    private func finish(_ data: Data?, cancelled: Bool) {
        process = nil
        if cancelled { state = .idle; return }
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            state = .failed("Couldn't run the speed test."); return
        }
        if let message = json["error_code"] as? String, json["dl_throughput"] == nil {
            state = .failed("Speed test failed (\(message))."); return
        }
        guard let dl = (json["dl_throughput"] as? NSNumber)?.doubleValue,
              let ul = (json["ul_throughput"] as? NSNumber)?.doubleValue else {
            state = .failed("No connection, or the test was blocked."); return
        }
        let rtt = (json["base_rtt"] as? NSNumber)?.doubleValue ?? 0
        state = .done(Result(download: dl / 1_000_000, upload: ul / 1_000_000, latency: rtt))
    }
}
