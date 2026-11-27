import Foundation

/// Fixed sizes from docs/DESIGN.md.
enum IslandLayout {
    static let wingsExtra: Double = 120
    /// The padlock and check sit this far toward the outer edge of their wing, clear of the notch's edge.
    static let wingInset: CGFloat = 8
    /// The lock-screen bar is a little taller than the notch so the padlock and check have equal padding on all
    /// sides: icon extent + 2 x pad. Lock: 24 pt tall open, pad 9. Check: 18 x 13 (+stroke), pad 13.
    static let lockBarExtra: CGFloat = 8
    static let lockInset: CGFloat = 13   // padlock centre, outward from the wing centre
    static let checkInset: CGFloat = 9.5 // check centre, outward from the wing centre
    /// Gap between the padlock's 17 pt body and the island's outer edge (30 - 13 - 8.5). The "⌘⇧" hint keeps the
    /// same gap on the left.
    static let lockEdgeGap: CGFloat = 60 / 2 - lockInset - 17 / 2
    /// Wing width for Focus / Wi-Fi / Bluetooth events: wide enough for a name.
    static let eventWing: Double = 120
    static let peekExtraWidth: Double = 16
    static let peekExtraHeight: Double = 6
    /// Hover over something showing (wings, wide bar, chin): it swells this much wider and taller, on a springy bubble.
    static let hoverSwellWidth: Double = 12
    static let hoverSwellHeight: Double = 3
    /// Volume and brightness in the wide bar: icon left, number right, and the 16-step bar in a short body below.
    static let levelBodyHeight: CGFloat = 26
    static let levelSideInset: CGFloat = 20
    /// The level row that grows under the unlock, the lock bar or the scan when volume or brightness changes then.
    static let levelTrayHeight: CGFloat = 34
    /// The lock-screen bar with a short body below spelling out the Command+Shift hint.
    static let lockHintBodyHeight: CGFloat = 28
    /// A notification's card under the stem, and the taller one a swipe down opens.
    static let notificationWidth: Double = 360
    static let notificationHeight: Double = 72
    /// Two or more stacked: the shape is this much deeper.
    static let notificationStackDepth: CGFloat = 8
    /// The card with the banner's buttons under the text.
    static let notificationActionsHeight: CGFloat = 36
    /// Waiting notifications as a pill at the top of the panel: 32 tall, 12 from the top (DESIGN.md "In the panel").
    static let notificationPillHeight: CGFloat = 44
    /// A Messages conversation in the panel.
    static let messagesBodyHeight: CGFloat = 300
    /// Search at its tallest: field 52, hairline, 300 of results, footer 28 (DESIGN.md "Search").
    static let searchMaxBodyHeight: CGFloat = 52 + 1 + 300 + 28
    /// Shazam's card with the song: artwork, title and artist under the stem.
    static let shazamCardWidth: Double = 360
    static let shazamCardHeight: Double = 76
    /// The AirPods case card: the earbuds and the case, their charge underneath.
    static let earbudsCardWidth: Double = 330
    static let earbudsCardHeight: Double = 124
    /// Quick info's chin: the time and battery, then Wi-Fi and Bluetooth on a line each (one line shorter without a
    /// Bluetooth device: `quickChinLine`).
    static let quickChinWidth: Double = 340
    static let quickChinHeight: Double = 82
    static let quickChinLine: Double = 22
    static let chinWidth: Double = 300
    static let chinHeight: Double = 36
    static let scanHeight: Double = 150
    static let expandedWidth: Double = 500
    static let expandedBodyHeight: CGFloat = 216
    /// Wi-Fi and Bluetooth lists get a taller body so they are not cramped.
    static let expandedListBodyHeight: CGFloat = 300
    /// The Display page with a keyboard backlight slider under the screen's.
    static let expandedDisplayBodyHeight: CGFloat = 280
    /// The Display page's extended brightness card and the gap under it.
    static let xdrCardRow: CGFloat = 80
    /// The extended brightness card itself (three lines of text).
    static let xdrCardHeight: CGFloat = 70
    /// The battery page: the charge, four stat tiles, the energy mode switch and a footer.
    static let expandedBatteryBodyHeight: CGFloat = 308
    /// Bezel mode: the floating panel's top margin (no notch to clear).
    static let floatingContentTop: CGFloat = 14
}

/// What the island is showing. Features set these; the shape morphs between them.
enum Presentation: Equatable {
    case closed, peek, wings, lockWings, lockHint, levelWings, eventWings, chin, scan, expanded, enrol, notification
    /// Quick info on hover (DESIGN.md "Quick info"): the wide bar when the menu bar has room, else a two-row chin.
    case quickBar, quickChin
    /// Shazam (DESIGN.md "Shazam"): the wide bar with a body while listening, the card with the song after; the store
    /// sizes it for the chin and the card.
    case shazam
    /// An AirPods case opened beside the Mac (DESIGN.md "AirPods case"): a card under the notch.
    case earbuds
}

/// Every dimension of the island shape. Each one is animated on its own channel.
/// - sw/sh: stem width/height (the stem is the notch; in wings it is the whole wide bar)
/// - bw/bh: body width/height below the stem
/// - tr/br: body top and bottom corner radii
/// - ic: concave inner curve radius where the stem meets the body
/// - y: top of the shape (bezel mode only: the floating card hangs below the menu bar; 0 everywhere else)
struct IslandMetrics: Equatable {
    var sw, sh, bw, bh, tr, br, ic: Double
    var y: Double = 0

    static let channelCount = 8

    subscript(i: Int) -> Double {
        get {
            switch i {
            case 0: sw
            case 1: sh
            case 2: bw
            case 3: bh
            case 4: tr
            case 5: br
            case 6: ic
            default: y
            }
        }
        set {
            switch i {
            case 0: sw = newValue
            case 1: sh = newValue
            case 2: bw = newValue
            case 3: bh = newValue
            case 4: tr = newValue
            case 5: br = newValue
            case 6: ic = newValue
            default: y = newValue
            }
        }
    }

    var width: Double { max(sw, bw) }
    var height: Double { sh + bh }

    static let zero = IslandMetrics(sw: 0, sh: 0, bw: 0, bh: 0, tr: 0, br: 0, ic: 0)

    static func + (a: IslandMetrics, b: IslandMetrics) -> IslandMetrics {
        var m = a
        for i in 0..<channelCount { m[i] += b[i] }
        return m
    }
}

extension Presentation {
    func metrics(notchWidth nw: Double, notchHeight nh: Double, bodyHeight: Double = Double(IslandLayout.expandedBodyHeight)) -> IslandMetrics {
        typealias L = IslandLayout
        switch self {
        case .closed:
            return IslandMetrics(sw: nw, sh: nh, bw: nw, bh: 0, tr: 0, br: 10, ic: 0)
        case .peek:
            let w = nw + L.peekExtraWidth
            return IslandMetrics(sw: w, sh: nh + L.peekExtraHeight, bw: w, bh: 0, tr: 0, br: 14, ic: 0)
        case .wings:
            let w = nw + L.wingsExtra
            return IslandMetrics(sw: w, sh: nh, bw: w, bh: 0, tr: 0, br: 12, ic: 0)
        case .lockWings:
            let w = nw + L.wingsExtra
            return IslandMetrics(sw: w, sh: nh + Double(L.lockBarExtra), bw: w, bh: 0, tr: 0, br: 14, ic: 0)
        case .lockHint:
            let w = nw + L.wingsExtra
            return IslandMetrics(sw: w, sh: nh + Double(L.lockBarExtra), bw: w, bh: Double(L.lockHintBodyHeight), tr: 0, br: 18, ic: 0)
        case .eventWings:
            let w = nw + 2 * L.eventWing
            return IslandMetrics(sw: w, sh: nh, bw: w, bh: 0, tr: 0, br: 12, ic: 0)
        case .levelWings, .quickBar, .shazam:
            let w = nw + L.wingsExtra
            return IslandMetrics(sw: w, sh: nh, bw: w, bh: Double(L.levelBodyHeight), tr: 0, br: 18, ic: 0)
        case .quickChin:
            return IslandMetrics(sw: nw, sh: nh, bw: L.quickChinWidth, bh: L.quickChinHeight, tr: 16, br: 18, ic: 10)
        case .chin:
            return IslandMetrics(sw: nw, sh: nh, bw: L.chinWidth, bh: L.chinHeight, tr: 16, br: 16, ic: 10) // all four corners 16
        case .notification:
            return IslandMetrics(sw: nw, sh: nh, bw: L.notificationWidth, bh: L.notificationHeight, tr: 16, br: 20, ic: 10)
        case .earbuds:
            return IslandMetrics(sw: nw, sh: nh, bw: L.earbudsCardWidth, bh: L.earbudsCardHeight, tr: 16, br: 26, ic: 10)
        case .scan:
            // The wide notch expanded downward, so the padlock in the wings stays visible above the scan.
            let w = nw + L.wingsExtra
            return IslandMetrics(sw: w, sh: nh + Double(L.lockBarExtra), bw: w, bh: L.scanHeight, tr: 0, br: 40, ic: 0)
        case .enrol:
            return IslandMetrics(sw: nw, sh: nh, bw: 380, bh: 214, tr: 16, br: 30, ic: 10)
        case .expanded:
            return IslandMetrics(sw: nw, sh: nh, bw: L.expandedWidth, bh: bodyHeight, tr: 16, br: 30, ic: 10)
        }
    }
}
