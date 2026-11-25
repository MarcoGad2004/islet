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

    /// Elapsed seconds now, advancing while playing.
    func position(at date: Date = Date()) -> Double {
        let e = playing ? elapsed + date.timeIntervalSince(timestamp) * max(rate, 1) : elapsed
        return duration > 0 ? min(max(e, 0), duration) : max(e, 0)
    }
}
