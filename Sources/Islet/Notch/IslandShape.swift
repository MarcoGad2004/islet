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
        // A body wider than the stem can only round its own height; one flush with the stem rounds the whole
        // island. Blend between the two over the last 3 pt, so the corners don't jump when a closing chin's width
        // lands on the notch's while the body is already sliding up.
        let flush = max(0, 1 - avail / 3)
        let maxBR = bh + sh * flush
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

/// Bezel mode (no notch): the island is a plain rounded card, `y` down from the top of the panel (the screen's top
/// edge), as wide as its body.
struct CardShape: Shape {
    var m: IslandMetrics

    static func frame(_ m: IslandMetrics, in rect: CGRect) -> CGRect {
        let w = max(m.sw, m.bw, 0), h = max(m.sh + m.bh, 0)
        return CGRect(x: rect.midX - w / 2, y: rect.minY + m.y, width: w, height: h)
    }

    static func radius(_ m: IslandMetrics, _ f: CGRect) -> CGFloat { max(0, min(m.br, f.width / 2, f.height / 2)) }

    /// How attached the card is to the top edge: 1 when its top is at the edge (the orb), 0 once it is 6 pt clear.
    static func attachment(_ f: CGRect) -> CGFloat { max(0, min(1, 1 - abs(f.minY) / 6)) }

    /// The card, rounded all round when it floats. Attached to the top edge it is shaped like the notch: square
    /// top corners that flare out into the edge, rounded only at the bottom.
    static func path(_ f: CGRect, radius r: CGFloat) -> Path {
        let a = attachment(f)
        guard a > 0, f.height > 0 else { return Path(roundedRect: f, cornerRadius: r, style: .continuous) }
        let k = 0.5523
        let tf = min(IslandShape.topFlare * a, f.height / 2)  // flare into the edge
        let rb = max(0, min(r, f.width / 2, f.height - tf))   // bottom corners
        let L = f.minX, R = f.maxX, T = f.minY, B = f.maxY
        var p = Path()
        p.move(to: CGPoint(x: L - tf, y: T))
        p.addLine(to: CGPoint(x: R + tf, y: T))
        p.addCurve(to: CGPoint(x: R, y: T + tf),
                   control1: CGPoint(x: R + tf - k * tf, y: T), control2: CGPoint(x: R, y: T + tf - k * tf))
        p.addLine(to: CGPoint(x: R, y: B - rb))
        p.addCurve(to: CGPoint(x: R - rb, y: B),
                   control1: CGPoint(x: R, y: B - rb + k * rb), control2: CGPoint(x: R - rb + k * rb, y: B))
        p.addLine(to: CGPoint(x: L + rb, y: B))
        p.addCurve(to: CGPoint(x: L, y: B - rb),
                   control1: CGPoint(x: L + rb - k * rb, y: B), control2: CGPoint(x: L, y: B - rb + k * rb))
        p.addLine(to: CGPoint(x: L, y: T + tf))
        p.addCurve(to: CGPoint(x: L - tf, y: T),
                   control1: CGPoint(x: L, y: T + tf - k * tf), control2: CGPoint(x: L - tf + k * tf, y: T))
        p.closeSubpath()
        return p
    }

    func path(in rect: CGRect) -> Path {
        let f = Self.frame(m, in: rect)
        return Self.path(f, radius: Self.radius(m, f))
    }
}

/// Bezel mode's black: the card, plus the liquid neck that joins it to the top edge while it is close to it (falling
/// out, the orb hanging from the edge, rising back in). A thin strip along the top edge and the card are blurred
/// together and cut at half opacity, so they merge like two drops where they meet; on their own the strip stays
/// below the cut and never shows. The card is drawn again on top, crisp, so only the neck comes from the blur.
struct BezelBackdrop: View {
    var m: IslandMetrics
    static let blur: CGFloat = 6

    var body: some View {
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size)
            let f = CardShape.frame(m, in: bounds)
            guard f.maxY > 0, f.width > 0, f.height > 0 else { return }
            let card = CardShape.path(f, radius: CardShape.radius(m, f))
            // Only near the edge: once the card floats well clear there is no neck to draw. Attached (the orb), the
            // card's own flare joins it to the edge, so the blurred neck fades out rather than smudging it.
            let neck = 1 - CardShape.attachment(f)
            if f.minY < Self.blur * 3 && neck > 0 {
                // The blur only matters where the strip meets the card. Clipped to that zone (the blur's reach,
                // 3 radii, beyond it), the filters work on a small area instead of the whole 560 x 450 pt panel on
                // every frame of the fall. What shows is the same: the card is drawn crisp over the rest.
                let reach = Self.blur * 3
                let zone = CGRect(x: f.minX - 40 - reach, y: 0, width: f.width + 80 + 2 * reach,
                                  height: min(f.maxY, f.minY + Self.blur * 5) + reach)
                var clipped = ctx
                clipped.clip(to: Path(zone))
                clipped.drawLayer { layer in
                    layer.opacity = neck
                    layer.addFilter(.alphaThreshold(min: 0.5, color: .black))
                    layer.addFilter(.blur(radius: Self.blur))
                    layer.fill(Path(CGRect(x: f.minX - 40, y: 0, width: f.width + 80, height: 4)), with: .color(.black))
                    layer.fill(card, with: .color(.black))
                }
            }
            ctx.fill(card, with: .color(.black))
        }
    }
}
