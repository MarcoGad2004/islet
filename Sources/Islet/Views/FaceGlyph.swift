import SwiftUI

/// A line-drawn face in four corner brackets, Face ID style (owner's choice, 2026-11-24, replacing the dot grid). The
/// face tilts with the head, blinks, breathes while it's looking, and turns into a check mark on success.
/// Drawn on a 100 x 100 grid centred on the origin, scaled to `size`.
struct FaceGlyph: View {
    var color: Color
    var size: CGFloat = 96
    /// Head direction, mirror-style: x right, y up, about -1...1. The features slide that way.
    var tilt: CGSize = .zero
    /// How far the features slide at a tilt of 1, in grid units.
    var reach: CGFloat = 8
    /// Blink now and then (the scan asks for a blink).
    var blinking = false
    /// Fade gently in and out (looking for a face, recognizing it).
    var breathing = false
    var checked = false

    var body: some View {
        TimelineView(.animation(paused: !breathing && !blinking)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // A blink every 1.6 s, the eyes shut for 0.22 s of it.
            let shut = blinking && !checked && t.truncatingRemainder(dividingBy: 1.6) < 0.22
            let glow = breathing && !checked ? 0.725 + 0.275 * cos(t * 2 * .pi / 1.6) : 1
            ZStack {
                GlyphShape(kind: .brackets).stroke(color, style: Self.line)
                ZStack {
                    GlyphShape(kind: .openEyes).stroke(color, style: Self.line).opacity(shut ? 0 : 1)
                    GlyphShape(kind: .shutEyes).stroke(color, style: Self.line).opacity(shut ? 1 : 0)
                    GlyphShape(kind: .noseAndMouth).stroke(color, style: Self.line)
                }
                .offset(x: max(-1.2, min(1.2, tilt.width)) * reach * size / 100,
                        y: -max(-1.2, min(1.2, tilt.height)) * reach * size / 100)
                .opacity(checked ? 0 : 1)
                .scaleEffect(checked ? 0.6 : 1)
                GlyphShape(kind: .check)
                    .trim(from: 0, to: checked ? 1 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            .opacity(glow)
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.18), value: tilt)
        .animation(.easeInOut(duration: 0.35), value: checked)
        .animation(.easeInOut(duration: 0.25), value: color)
    }

    private static let line = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
}

private struct GlyphShape: Shape {
    enum Kind { case brackets, openEyes, shutEyes, noseAndMouth, check }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .brackets:
            let b: CGFloat = 36, k: CGFloat = 12
            for (x, y) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                p.move(to: CGPoint(x: x * b, y: y * (b - k)))
                p.addLine(to: CGPoint(x: x * b, y: y * b))
                p.addLine(to: CGPoint(x: x * (b - k), y: y * b))
            }
        case .openEyes:
            for x in [-11.5, 11.5] { p.move(to: CGPoint(x: x, y: -12)); p.addLine(to: CGPoint(x: x, y: -6)) }
        case .shutEyes:
            for x in [-11.5, 11.5] { p.move(to: CGPoint(x: x - 4, y: -8)); p.addLine(to: CGPoint(x: x + 4, y: -8)) }
        case .noseAndMouth:
            p.move(to: CGPoint(x: 1, y: -10)); p.addLine(to: CGPoint(x: 1, y: 2)); p.addLine(to: CGPoint(x: -3, y: 2))
            p.move(to: CGPoint(x: -11, y: 11)); p.addQuadCurve(to: CGPoint(x: 11, y: 11), control: CGPoint(x: 0, y: 19))
        case .check:
            p.move(to: CGPoint(x: -14, y: 1)); p.addLine(to: CGPoint(x: -4, y: 11)); p.addLine(to: CGPoint(x: 15, y: -10))
        }
        return p.applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: rect.width / 100, y: rect.height / 100))
    }
}
