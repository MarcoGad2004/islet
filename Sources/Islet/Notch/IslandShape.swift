import SwiftUI

/// The whole island as one path: stem + body + concave inner curves.
/// Drawn centred horizontally in its rect and attached to the top edge.
struct IslandShape: Shape {
    var m: IslandMetrics
    static let topFlare: Double = 6

    func path(in rect: CGRect) -> Path {
        let k = 0.5523 // circle approximation for cubic curves
        let cx = rect.midX
        let sw = max(m.sw, 0), sh = max(m.sh, 0)
        let bw = max(m.bw, sw), bh = max(m.bh, 0)
        let avail = (bw - sw) / 2

        // Inner curve and top corner share the flat top of the body; shrink both if it is too short.
        var ic = max(m.ic, 0), tr = max(m.tr, 0)
        if ic + tr > 0 { let s = min(1, avail / (ic + tr)); ic *= s; tr *= s }
        // The real notch flares outward where it meets the top edge; mimic that with a small concave curve.
        let tf = min(IslandShape.topFlare, sh / 2)
        ic = min(ic, sh - tf)

        let yS = sh, yB = sh + bh
        let maxBR = (bw - sw > 0.5) ? bh : yB
        let br = min(max(m.br, 0), bw / 2, maxBR)

        let L = cx - sw / 2, R = cx + sw / 2
        let BL = cx - bw / 2, BR = cx + bw / 2

        var p = Path()
        p.move(to: CGPoint(x: L - tf, y: 0))
        p.addLine(to: CGPoint(x: R + tf, y: 0))
        p.addCurve(to: CGPoint(x: R, y: tf),
                   control1: CGPoint(x: R + tf - k * tf, y: 0),
                   control2: CGPoint(x: R, y: tf - k * tf))
        p.addLine(to: CGPoint(x: R, y: yS - ic))
        // concave curve out to the body top (right)
        p.addCurve(to: CGPoint(x: R + ic, y: yS),
                   control1: CGPoint(x: R, y: yS - ic + k * ic),
                   control2: CGPoint(x: R + ic - k * ic, y: yS))
        p.addLine(to: CGPoint(x: BR - tr, y: yS))
        p.addCurve(to: CGPoint(x: BR, y: yS + tr),
                   control1: CGPoint(x: BR - tr + k * tr, y: yS),
                   control2: CGPoint(x: BR, y: yS + tr - k * tr))
        p.addLine(to: CGPoint(x: BR, y: yB - br))
        p.addCurve(to: CGPoint(x: BR - br, y: yB),
                   control1: CGPoint(x: BR, y: yB - br + k * br),
                   control2: CGPoint(x: BR - br + k * br, y: yB))
        p.addLine(to: CGPoint(x: BL + br, y: yB))
        p.addCurve(to: CGPoint(x: BL, y: yB - br),
                   control1: CGPoint(x: BL + br - k * br, y: yB),
                   control2: CGPoint(x: BL, y: yB - br + k * br))
        p.addLine(to: CGPoint(x: BL, y: yS + tr))
        p.addCurve(to: CGPoint(x: BL + tr, y: yS),
                   control1: CGPoint(x: BL, y: yS + tr - k * tr),
                   control2: CGPoint(x: BL + tr - k * tr, y: yS))
        p.addLine(to: CGPoint(x: L - ic, y: yS))
        // concave curve up into the stem (left)
        p.addCurve(to: CGPoint(x: L, y: yS - ic),
                   control1: CGPoint(x: L - ic + k * ic, y: yS),
                   control2: CGPoint(x: L, y: yS - ic + k * ic))
        p.addLine(to: CGPoint(x: L, y: tf))
        p.addCurve(to: CGPoint(x: L - tf, y: 0),
                   control1: CGPoint(x: L, y: tf - k * tf),
                   control2: CGPoint(x: L - tf + k * tf, y: 0))
        p.closeSubpath()
        return p
    }
}
