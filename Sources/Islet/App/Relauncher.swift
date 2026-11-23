import AppKit
import os

/// Opens the app again once this copy has quit: for "Restart Dynamic Peninsula", and when System Settings quits it to
/// apply a permission ("Quit & Reopen"), which doesn't always bring it back by itself.
enum Relauncher {
    private static let log = Logger(subsystem: "com.marcogad.islet", category: "relaunch")

    /// System Settings and its privacy pane (an extension process on recent macOS).
    private static let settingsIDs = ["com.apple.systempreferences", "com.apple.settings."]

    /// Whether the quit being handled now is System Settings' Quit & Reopen. Call it while the quit is being handled
    /// (`applicationShouldTerminate`), when its Apple event is still current.
    static func quitIsFromSystemSettings() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication else { return false }
        let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr).map { pid_t($0.int32Value) } ?? 0
        let sender = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
        log.info("quit asked by \(sender ?? "unknown", privacy: .public) (pid \(pid))")
        guard let sender else { return false }
        return settingsIDs.contains { sender.hasPrefix($0) }
    }

    /// Starts a small waiter that opens the app once this process has gone. It runs in its own session, so it isn't
    /// stopped along with the app as it quits (a plain child process can be). If something else has already reopened
    /// the app by then, `open` only brings that copy forward.
    static func reopenAfterExit() {
        let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /bin/sleep 0.3; /usr/bin/open \"$0\""
        let args = ["/bin/sh", "-c", script, Bundle.main.bundlePath, String(getpid())]
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var cArgs = args.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, "/bin/sh", nil, &attr, &cArgs, environ)
        if result == 0 { log.info("reopen waiter started (pid \(pid))") }
        else { log.error("reopen waiter failed to start: \(result)") }
    }

    /// Quits and comes back.
    @MainActor static func restart() {
        reopenAfterExit()
        NSApp.terminate(nil)
    }
}
