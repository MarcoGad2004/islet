import AppKit

struct MediaInfo: Equatable {
    var bundleID: String
    var title: String
    var artist: String
    var album: String
    var playing: Bool
    var duration: Double
    /// Elapsed seconds at `timestamp`.
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var artwork: NSImage?
    /// The player's shuffle (any mode but off) and repeat (1 off, 2 one track, 3 all) as it reports them.
    var shuffle = false
    var repeatMode = 1
    /// False when the player has said nothing about where it is (a browser's update can leave out the time and length).
    var positionKnown = true

    /// The player is a web browser (Safari, Chrome, Firefox, Zen, Arc...): it plays video and web audio through the
    /// browser's media session, which answers play, pause, skip and seek but not shuffle or repeat.
    var isBrowser: Bool { Self.isBrowser(bundleID) }
    /// How far the skip buttons jump: 10 s in a browser (what a video's own skip does), 15 s in a music or podcast app.
    var skipSeconds: Double { isBrowser ? 10 : 15 }

    static func isBrowser(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return browserPrefixes.contains { id.hasPrefix($0) }
    }

    private static let browserPrefixes = [
        "com.apple.safari", "com.google.chrome", "org.chromium.chromium", "org.mozilla.", "app.zen-browser.",
        "io.gitlab.librewolf", "company.thebrowser.", "com.microsoft.edgemac", "com.brave.browser", "com.operasoftware.",
        "com.vivaldi.", "com.kagi.kagimacos", "com.duckduckgo.macos.browser", "net.waterfox.", "org.torproject.",
        "com.sigmaos.", "com.pushplaylabs.sidekick", "ru.yandex.desktop.yandex-browser", "app.helium.",
    ]

    /// Elapsed seconds now, advancing while playing.
    func position(at date: Date = Date()) -> Double {
        let e = playing ? elapsed + date.timeIntervalSince(timestamp) * max(rate, 1) : elapsed
        return duration > 0 ? min(max(e, 0), duration) : max(e, 0)
    }
}
