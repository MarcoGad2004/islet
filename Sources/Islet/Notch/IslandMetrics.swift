import Foundation

/// Fixed sizes from docs/DESIGN.md.
enum IslandLayout {
    static let wingsExtra: Double = 120
    static let peekExtraWidth: Double = 16
    static let peekExtraHeight: Double = 6
    static let chinWidth: Double = 300
    static let chinHeight: Double = 36
    static let scanHeight: Double = 150
    static let expandedWidth: Double = 500
    static let expandedBodyHeight: CGFloat = 216
}

/// What the island is showing. Features set these; the shape morphs between them.
enum Presentation: Equatable {
    case closed, peek, wings, chin, scan, expanded, enrol
}

/// Every dimension of the island shape. Each one is animated on its own channel.
/// - sw/sh: stem width/height (the stem is the notch; in wings it is the whole wide bar)
/// - bw/bh: body width/height below the stem
/// - tr/br: body top and bottom corner radii
/// - ic: concave inner curve radius where the stem meets the body
struct IslandMetrics: Equatable {
    var sw, sh, bw, bh, tr, br, ic: Double

    static let channelCount = 7

    subscript(i: Int) -> Double {
        get {
            switch i {
            case 0: sw
            case 1: sh
            case 2: bw
            case 3: bh
            case 4: tr
            case 5: br
            default: ic
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
            default: ic = newValue
            }
        }
    }

    var width: Double { max(sw, bw) }
    var height: Double { sh + bh }
}

extension Presentation {
    func metrics(notchWidth nw: Double, notchHeight nh: Double) -> IslandMetrics {
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
        case .chin:
            return IslandMetrics(sw: nw, sh: nh, bw: L.chinWidth, bh: L.chinHeight, tr: 10, br: 16, ic: 10)
        case .scan:
            // The wide notch expanded downward, so the padlock in the wings stays visible above the scan.
            let w = nw + L.wingsExtra
            return IslandMetrics(sw: w, sh: nh, bw: w, bh: L.scanHeight, tr: 0, br: 40, ic: 0)
        case .enrol:
            return IslandMetrics(sw: nw, sh: nh, bw: 380, bh: 214, tr: 16, br: 30, ic: 10)
        case .expanded:
            return IslandMetrics(sw: nw, sh: nh, bw: L.expandedWidth, bh: Double(L.expandedBodyHeight), tr: 16, br: 30, ic: 10)
        }
    }
}
