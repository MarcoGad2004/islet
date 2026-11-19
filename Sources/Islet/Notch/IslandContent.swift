import SwiftUI

/// A short event or persistent state shown in the wings or chin.
enum IslandContent {
    case unlock(start: Date)
    /// On the lock screen: a white closed padlock on the right of the wings.
    case locked
    case level(LevelState)
    case charge(ChargeEvent)
    case event(IslandEvent)
    /// Joining a network or hotspot picked in the panel: live progress, then the result.
    case progress(ConnectionProgress)
    case media

    /// Identity for cross-fades: content of the same kind updates in place.
    var kind: String {
        switch self {
        case .unlock: "unlock"
        case .locked: "locked"
        case .level: "level"
        case .charge(let c): "charge-\(c.kind)"
        case .event(let e): "event-\(e.kind)"
        case .progress: "progress"
        case .media: "media"
        }
    }
}

enum ExpandedPage { case media, displaySound }

struct LevelState: Equatable {
    enum Kind { case volume, brightness, keyboard }
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

/// Focus on/off, Wi-Fi connected, Bluetooth device connected: shown like a charging event. A Personal Hotspot
/// connection uses the wide bar with a body under it, like volume, so the phone's name has room.
struct IslandEvent: Equatable {
    enum Kind { case focusOn, focusOff, wifi, hotspot, bluetooth }
    var kind: Kind
    var icon: String
    /// The name: the Focus, the network or the device.
    var title: String
    /// Short status word for the chin: "On", "Off", "Connected".
    var detail: String
    /// A Focus's own colour; the kind's colour when nil.
    var tint: Color? = nil
    var seconds: Double { 3 }
}

/// A join (or an update) in progress. Updates in place (one content kind), so the notch doesn't remount between steps.
struct ConnectionProgress: Equatable {
    enum State: Equatable {
        case working(String)
        case done
        case failed(String)
    }
    var name: String
    var hotspot: Bool
    var state: State
    /// Not a network join: its own symbol and colour, and what the result says.
    var icon: String? = nil
    var tint: Color? = nil
    var doneText: String? = nil
    /// The result can be clicked (the update's "What's new"): the button's label.
    var actionLabel: String? = nil
    /// How long the result stays; nil for the usual 2.5 s.
    var hold: Double? = nil

    /// The line under the wings, or beside the icon in the chin.
    var text: String {
        switch state {
        case .working(let step): step
        case .done: doneText ?? "Connected to \(name)"
        case .failed(let message): message
        }
    }
}
