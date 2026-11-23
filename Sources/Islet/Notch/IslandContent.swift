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
    /// A banner taken from Notification Center (DESIGN.md "Notifications"): the card under the notch.
    case notification(NotificationItem)
    /// Shazam listening, then the song it found (DESIGN.md "Shazam").
    case shazam(ShazamState)
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
        case .notification: "notification" // a new one fades across inside the card, not by remounting
        case .shazam: "shazam" // listening turns into the result in place, so its pieces can move
        case .media: "media"
        }
    }
}

enum ExpandedPage { case media, displaySound, notifications, messages, inbox, search }

/// One banner, read through Accessibility (RESEARCH.md Q27).
struct NotificationItem: Equatable, Identifiable {
    let id: UUID
    var app: String
    var title: String
    var subtitle: String?
    var body: String
    var icon: NSImage?
    /// The app, to open it when the banner itself is already gone.
    var appURL: URL?
    /// The banner's own buttons besides Show and Close (Duo's Deny and Approve), in its order.
    var actions: [String] = []
    /// The banner's header says "TIME SENSITIVE".
    var timeSensitive = false
    /// Mirrored from the iPhone (the banner ends "from iPhone").
    var fromIPhone = false

    /// The card's one line: "Subtitle · Body".
    var line: String { [subtitle, body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
    var heading: String { title.isEmpty ? app : title }
    /// From Messages: it can open as a conversation in the notch.
    var isMessages: Bool { app == "Messages" || appURL?.lastPathComponent == "Messages.app" }
}

struct LevelState: Equatable {
    enum Kind { case volume, brightness, keyboard }
    var kind: Kind
    /// 0...1
    var value: Double
    var muted = false
    /// 0...16 filled steps of the bar.
    var steps: Int { Int((value * 16).rounded()) }

    /// The symbol beside the bar.
    var symbol: String {
        switch kind {
        case .brightness: "sun.max.fill"
        case .keyboard: value == 0 ? "light.min" : "light.max"
        case .volume: muted || value == 0 ? "speaker.slash.fill" : (value < 0.34 ? "speaker.wave.1.fill" : (value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
        }
    }
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

/// Shazam in the notch: listening, then what it heard. One content kind throughout, so the glyph can fly from the wing
/// into the artwork's place.
struct ShazamState: Equatable {
    enum Phase: Equatable {
        case listening
        case match(ShazamSong)
        case noMatch
        case micDenied
        case failed(String)
    }
    var phase = Phase.listening
    /// Pulled in from the right: the mark sits in the right wing and the equaliser in the left.
    var fromRight = false
    /// Pulled in with two fingers: the mark is already in place, so the island doesn't fade it in.
    var pulled = false
    /// When listening began, for the ripples' clock.
    var started = Date()

    var song: ShazamSong? { if case .match(let s) = phase { s } else { nil } }
    var listening: Bool { phase == .listening }

    /// The line in the body (or the chin) while there's no song.
    var text: String {
        switch phase {
        case .listening: "Listening…"
        case .match(let s): s.title
        case .noMatch: "No match. Try closer to the sound"
        case .micDenied: "Allow the microphone in Settings ›"
        case .failed(let m): m
        }
    }

    /// How long the result stays.
    var hold: Double {
        switch phase {
        case .listening: .infinity
        case .match: 8
        case .noMatch: 3
        case .micDenied, .failed: 4
        }
    }
}

/// Two fingers dragging Shazam in over the idle notch, before it listens (DESIGN.md "Shazam", "Pulling it in").
struct ShazamPull: Equatable {
    /// +1 fingers moving right (the mark comes in from the left), -1 left; 0 until they pick a side.
    var dir = 0
    /// 0 untouched, 0.5 the commit point (the mark home, the ring full), toward 1 the further past it.
    var progress = 0.0
    /// Let go short of the commit point: springing back out.
    var releasing = false
    /// The pull has caught (the first light tick has played).
    var caught = false

    var armed: Bool { progress >= 0.5 }
    /// How far in the mark is, 0 to 1 at the commit point.
    var reach: Double { min(max(progress / 0.5, 0), 1) }
}

/// Two fingers dragging up or down over Shazam while it listens, to stop it (DESIGN.md "Shazam", "Stopping it").
struct ShazamDrag: Equatable {
    /// -1 up (pushed back into the notch), +1 down (pulled off the bottom); 0 until the fingers pick a way.
    var dir = 0
    /// 0 untouched, 0.5 the commit point, toward 1 past it.
    var progress = 0.0
    var releasing = false
    var caught = false

    var armed: Bool { progress >= 0.5 }
    var reach: Double { min(max(progress / 0.5, 0), 1) }
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
    /// The whole job's progress, 0...1 (an update): shown as a bar that becomes a check when it is done.
    var fraction: Double? = nil

    /// The line under the wings, or beside the icon in the chin.
    var text: String {
        switch state {
        case .working(let step): step
        case .done: doneText ?? "Connected to \(name)"
        case .failed(let message): message
        }
    }
}
