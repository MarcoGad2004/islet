import Foundation

/// Shuffle and repeat for the two music apps that script them. The system's now-playing commands don't reach them (Spotify
/// ignores the adapter's shuffle, repeat and toggle commands and reports neither state), so Islet asks the app itself,
/// through `osascript`: read the real state, set it. macOS asks once per app for permission to control it.
enum PlayerControls {
    enum App { case music, spotify }

    static func app(_ bundleID: String) -> App? {
        switch bundleID {
        case "com.apple.Music": .music
        case "com.spotify.client": .spotify
        default: nil
        }
    }

    /// Off, one track, all: the values `MediaInfo.repeatMode` uses (1, 2, 3). Spotify only has off and on (all).
    static func nextRepeat(_ app: App, from mode: Int) -> Int {
        switch app {
        case .spotify: mode == 1 ? 3 : 1
        case .music: [1: 3, 3: 2, 2: 1][mode] ?? 3
        }
    }

    /// The app's own shuffle and repeat, nil when it isn't running, doesn't answer or Islet isn't allowed to ask.
    static func read(_ bundleID: String) async -> (shuffle: Bool, repeatMode: Int)? {
        guard let app = app(bundleID) else { return nil }
        let script = switch app {
        case .music: "tell application id \"com.apple.Music\" to return (shuffle enabled as text) & \",\" & (song repeat as text)"
        case .spotify: "tell application id \"com.spotify.client\" to return (shuffling as text) & \",\" & (repeating as text)"
        }
        guard let out = await osascript(script) else { return nil }
        return parse(out, app: app)
    }

    static func parse(_ out: String, app: App) -> (shuffle: Bool, repeatMode: Int)? {
        let parts = out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, ["true", "false"].contains(parts[0]) else { return nil }
        let repeatMode: Int
        switch app {
        case .spotify: repeatMode = parts[1] == "true" ? 3 : 1
        case .music: repeatMode = ["off": 1, "one": 2, "all": 3][parts[1]] ?? 1
        }
        return (parts[0] == "true", repeatMode)
    }

    static func setShuffle(_ bundleID: String, _ on: Bool) async {
        guard let app = app(bundleID) else { return }
        switch app {
        case .music: _ = await osascript("tell application id \"com.apple.Music\" to set shuffle enabled to \(on)")
        case .spotify: _ = await osascript("tell application id \"com.spotify.client\" to set shuffling to \(on)")
        }
    }

    static func setRepeat(_ bundleID: String, _ mode: Int) async {
        guard let app = app(bundleID) else { return }
        switch app {
        case .music:
            let word = [1: "off", 2: "one", 3: "all"][mode] ?? "off"
            _ = await osascript("tell application id \"com.apple.Music\" to set song repeat to \(word)")
        case .spotify:
            _ = await osascript("tell application id \"com.spotify.client\" to set repeating to \(mode != 1)")
        }
    }

    /// Runs a script with `osascript` off the main thread; nil when it fails or takes over 4 s.
    private static func osascript(_ script: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { cont.resume(returning: nil); return }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: killer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                cont.resume(returning: p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }
}
