import AppKit
import SwiftUI

/// The glass look (1.3, DESIGN.md "Glass"). The island stays solid black down to the bottom of the notch, so it still
/// reads as the notch, then fades into glass: the desktop behind shows through, blurred and smoked, with a light rim
/// and a faint coloured glow along the lower edge.
enum GlassLook {
    static let key = "glassLook"
    /// How far below the notch the black takes to fade into glass.
    static let fade: CGFloat = 28
    /// Black left over the glass, so white text stays readable on a light wallpaper.
    static let smoke: Double = 0.5
    /// Opacity of the coloured glow along the edge.
    static let glow: Double = 0.32
}

extension EnvironmentValues {
    /// True while the island draws the glass look; content swaps its solid grey cards for translucent ones.
    @Entry var isletGlass = false
}

/// The panel's tiles and pills: solid dark grey on black, a translucent white on glass.
struct IsletCardFill: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.isletGlass ? Color.white.opacity(0.1) : Color(hex: 0x1C1C1E)
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
            let top = min(notchHeight / h, 1)
            let bottom = min((notchHeight + GlassLook.fade) / h, 1)
            // Black down to the notch's bottom, then easing off to the smoke over `fade`.
            let black = LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: top),
                .init(color: .black.opacity(GlassLook.smoke), location: max(bottom, top + 0.0001)),
                .init(color: .black.opacity(GlassLook.smoke), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // The rest only shows where the glass does.
            let below = LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: top),
                .init(color: .white, location: max(bottom, top + 0.0001)),
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
