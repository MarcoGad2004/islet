import AppKit
import SwiftUI

/// The glass look (1.3, DESIGN.md "Glass"), after Siri's island on the iPhone: the island is black almost all the way
/// down, and only a strip along the bottom edge fades into glass, the desktop behind showing through blurred, with a
/// light rim and a faint coloured glow. The panel's tiles are glass too.
enum GlassLook {
    static let key = "glassLook"
    /// The glass strip is this share of the island's height below the notch, within `minStrip`...`maxStrip`.
    static let stripShare: CGFloat = 0.3
    static let minStrip: CGFloat = 10
    static let maxStrip: CGFloat = 44
    /// Black left at the very bottom of the strip.
    static let smoke: Double = 0.12
    /// Opacity of the coloured glow along the edge.
    static let glow: Double = 0.3
}

extension EnvironmentValues {
    /// True while the island draws the glass look; content swaps its solid grey cards for translucent ones.
    @Entry var isletGlass = false
}

/// The panel's tiles and pills, as a background: solid dark grey, or glass with the glass look (Liquid Glass on macOS
/// 26 and later, a translucent white with a hairline edge before that).
struct IsletCard<S: Shape>: View {
    var shape: S
    @Environment(\.isletGlass) private var glass

    var body: some View {
        if glass {
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular.tint(Color.white.opacity(0.06)), in: shape)
            } else {
                shape.fill(Color.white.opacity(0.08)).overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.8))
            }
        } else {
            shape.fill(Color(hex: 0x1C1C1E))
        }
    }
}

/// The island's fill with the glass look. Laid out like the black fill it replaces: the whole panel, shape at the top
/// centre.
struct GlassIsland: View {
    var m: IslandMetrics
    var notchHeight: CGFloat

    var body: some View {
        let shape = IslandShape(m: m)
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            // The strip: the bottom of the island, never reaching up into the notch.
            let underNotch = max(0, m.height - notchHeight)
            let strip = min(underNotch, max(GlassLook.minStrip, min(GlassLook.maxStrip, underNotch * GlassLook.stripShare)))
            let end = min(m.height / h, 1)
            let start = min(max(0, m.height - strip) / h, end)
            let mid = start + (end - start) * 0.5
            let eps = 0.0001
            // Black down to the strip, then easing off to the smoke at the bottom edge.
            let black = LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: start),
                .init(color: .black.opacity(0.7), location: mid + eps),
                .init(color: .black.opacity(GlassLook.smoke), location: end + 2 * eps),
                .init(color: .black.opacity(GlassLook.smoke), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // The rim and glow only show on the strip.
            let below = LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: start),
                .init(color: .white, location: end + eps),
                .init(color: .white, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            let centre = UnitPoint(x: 0.5, y: min(m.height / 2 / h, 1))

            ZStack {
                GlassBackdrop(shape: shape)
                shape.fill(black)
                // The glow: a soft band of colour just inside the edge, like Siri's.
                shape.stroke(AngularGradient(colors: [.isletCyan, Color(hex: 0x5E5CE6), Color(hex: 0xFF5EA8),
                                                      Color(hex: 0xFF9F0A), .isletCyan], center: centre),
                             lineWidth: 8)
                    .blur(radius: 6)
                    .opacity(GlassLook.glow)
                    .clipShape(shape)
                    .mask(below)
                // The rim: a hairline of light catching the edge.
                shape.stroke(Color.white.opacity(0.28), lineWidth: 1.2)
                    .clipShape(shape)
                    .mask(below)
            }
        }
        .allowsHitTesting(false)
    }
}

/// What's behind the island, blurred: Liquid Glass on macOS 26 and later, the dark HUD material before that.
private struct GlassBackdrop<S: Shape>: View {
    var shape: S

    var body: some View {
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            BehindWindowBlur().clipShape(shape)
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
