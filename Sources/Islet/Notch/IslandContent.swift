import Foundation

/// A short event or persistent state shown in the wings or chin.
enum IslandContent {
    case unlock(start: Date)
    /// On the lock screen: a white closed padlock on the right of the wings.
    case locked
    case level(LevelState)
    case charge(ChargeEvent)
    case media

    /// Identity for cross-fades: content of the same kind updates in place.
    var kind: String {
        switch self {
        case .unlock: "unlock"
        case .locked: "locked"
        case .level: "level"
        case .charge(let c): "charge-\(c.kind)"
        case .media: "media"
        }
    }
}

enum ExpandedPage { case media, displaySound }

struct LevelState: Equatable {
    enum Kind { case volume, brightness }
    var kind: Kind
    /// 0...1
    var value: Double
    var muted = false
    /// 0...16 filled steps of the bar.
    var steps: Int { Int((value * 16).rounded()) }
}

struct ChargeEvent: Equatable {
    enum Kind { case connected, full, low }
    var kind: Kind
    var percent: Int
    var minutesToFull: Int?

    var seconds: Double {
        switch kind {
        case .connected, .full: 3
        case .low: 4
        }
    }
}
