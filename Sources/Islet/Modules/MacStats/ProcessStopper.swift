import AppKit
import Observation

/// Quits a row of a "Using the most" list (DESIGN.md "Mac Stats (1.7)", Quitting from the lists): an app as the Dock's
/// Quit does, so it can still ask about unsaved work; anything else with SIGTERM. Only if it's still there a few seconds
/// later does the row offer Force Quit.
@MainActor @Observable
final class ProcessStopper {
    static let shared = ProcessStopper()

    enum State: Equatable {
        case quitting
        /// Asked to quit and still running: Force Quit is offered.
        case stubborn
    }

    private(set) var states: [String: State] = [:]
    /// How long a quit gets before Force Quit is offered.
    static let patience: Duration = .seconds(4)

    /// Not macOS's own processes, nothing of another user or root, and not Dynamic Peninsula itself.
    static func canStop(_ g: ProcessGroup) -> Bool {
        guard !g.id.hasPrefix("macos:"), !g.pids.isEmpty, !g.pids.contains(getpid()) else { return false }
        if let app = g.appPath {
            guard !app.hasPrefix("/System/"), app != Bundle.main.bundlePath else { return false }
            if !apps(g).isEmpty { return true }
        }
        // Signal 0 checks the right to signal it without sending anything.
        return g.pids.allSatisfy { kill($0, 0) == 0 }
    }

    func quit(_ g: ProcessGroup) {
        guard Self.canStop(g), states[g.id] == nil else { return }
        states[g.id] = .quitting
        let apps = Self.apps(g)
        if apps.isEmpty {
            for pid in g.pids { kill(pid, SIGTERM) }
        } else {
            for app in apps { app.terminate() }
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.patience)
            guard let self, self.states[g.id] == .quitting else { return }
            self.states[g.id] = Self.alive(g) ? .stubborn : nil
        }
    }

    func forceQuit(_ g: ProcessGroup) {
        guard Self.canStop(g) || states[g.id] != nil else { return }
        let apps = Self.apps(g)
        for app in apps { app.forceTerminate() }
        for pid in g.pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        states[g.id] = .quitting
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.states[g.id] = nil
        }
    }

    func state(_ g: ProcessGroup) -> State? { states[g.id] }

    /// The running app the row is, if it's one.
    private static func apps(_ g: ProcessGroup) -> [NSRunningApplication] {
        guard let path = g.appPath else { return [] }
        return NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path }
    }

    private static func alive(_ g: ProcessGroup) -> Bool {
        let apps = apps(g)
        if !apps.isEmpty { return apps.contains { !$0.isTerminated } }
        return g.pids.contains { kill($0, 0) == 0 }
    }
}
