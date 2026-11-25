import SwiftUI

// Media peek, skip and previous (DESIGN.md "Media peek" and "Skip and previous").

/// Skip forward, or back when mirrored: three triangles, two showing. Each push slides them one step on, the back one
/// fading in and the front one out, so it ends looking as it started.
struct SkipGlyph: View {
    var forward: Bool
    var size: CGFloat
    /// 0...1: how far the fingers have pulled; the triangles lean a little that way.
    var lean: Double = 0
    var armed = false
    var pushes = 0
    var color: Color = .isletText
    /// Inside `SkipIndicator` the ring shows the state, so the triangles stay at full strength.
    var dimsUntilArmed = true
    @State private var shift: CGFloat = 0

    var body: some View {
        let step = size * 9 / 24, w = size * 8.5 / 24, h = size * 11 / 24
        let lean = CGFloat(lean) * size * 2.5 / 24
        ZStack {
            tri(w, h).offset(x: -size * 13.75 / 24 + step * shift + lean).opacity(Double(shift))
            tri(w, h).offset(x: -size * 4.75 / 24 + step * shift + lean)
            tri(w, h).offset(x: size * 4.25 / 24 + step * shift + lean).opacity(Double(1 - shift))
        }
        .frame(width: size, height: size)
        .clipped()
        .scaleEffect(x: forward ? 1 : -1, y: 1)
        .opacity(armed || !dimsUntilArmed ? 1 : 0.55)
        .scaleEffect(armed || !dimsUntilArmed ? 1 : 0.9)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: armed)
        .onChange(of: pushes) { _, _ in
            shift = 0
            withAnimation(.easeOut(duration: 0.38)) { shift = 1 } completion: {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { shift = 0 }
            }
        }
    }

    private func tri(_ w: CGFloat, _ h: CGFloat) -> some View {
        Triangle().fill(color).frame(width: w, height: h)
    }

    private struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}

/// The skip icon inside a ring that fills as the fingers pull. When it's full the swipe will register: the ring becomes
/// a solid white disc with the icon cut in dark, with a pop. Let go before that and nothing happens.
struct SkipIndicator: View {
    var forward: Bool
    var size: CGFloat
    /// The pull, 0...1 (the line is at 0.5).
    var progress: Double
    var armed: Bool
    var pushes: Int

    var body: some View {
        let fill = SkipState.clamp(progress / 0.5)
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.5)
            Circle().trim(from: 0, to: armed ? 1 : fill)
                .stroke(Color.isletText, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(x: forward ? 1 : -1, y: 1)
            Circle().fill(Color.isletText).scaleEffect(armed ? 1 : 0.4).opacity(armed ? 1 : 0)
            SkipGlyph(forward: forward, size: size * 0.62, lean: armed ? 0 : fill, armed: true, pushes: pushes,
                      color: armed ? .black : .isletText, dimsUntilArmed: false)
                .opacity(armed ? 1 : 0.5 + 0.5 * fill)
        }
        .frame(width: size, height: size)
        .scaleEffect(armed ? 1.08 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.55), value: armed)
    }
}

/// One side slot of the media layout (the artwork on the left, the app icon on the right). On a swipe toward its side
/// it makes way for the skip icon: skip on the right, previous on the left.
struct MediaSlot<Content: View>: View {
    let store: IslandStore
    /// Right slot (skip) or left (previous).
    var forward: Bool
    var iconSize: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        let s = store.skip
        let mine = s.map { $0.dir == (forward ? 1 : -1) } ?? false
        let taken = mine ? s!.slotTaken : 0
        ZStack {
            content.opacity(1 - taken).scaleEffect(1 - 0.35 * taken)
            if mine, let s {
                SkipIndicator(forward: forward, size: 22, progress: s.landedFade == nil ? s.progress : 1,
                              armed: s.armed || s.landedFade != nil, pushes: s.pushes)
                    .opacity(s.iconOpacity)
                    .scaleEffect(0.6 + 0.4 * SkipState.clamp(s.progress * 2))
            }
        }
    }
}

/// The song's name in the bar under the notch. On a swipe it rolls: the current name out the way the fingers go, and
/// "Next song" or "Previous song" in from the other side (the player only names the new song once it plays). After
/// landing, the real name fades in over it.
struct MediaTitleLane: View {
    let store: IslandStore
    var fontSize: CGFloat
    /// How far apart the two names sit on the strip.
    var spacing: CGFloat

    var body: some View {
        let title = store.media.map { $0.artist.isEmpty ? $0.title : "\($0.title) · \($0.artist)" } ?? ""
        ZStack {
            if let s = store.skip, s.dir != 0 {
                let finger: CGFloat = s.dir == 1 ? -1 : 1
                let label = s.dir == 1 ? "Next song" : "Previous song"
                if let f = s.landedFade {
                    let k = SkipState.clamp(f / 0.4)
                    name(label, secondary: true).opacity(1 - k)
                    name(title, secondary: false).opacity(k)
                } else {
                    let p = s.progress, x = finger * spacing * CGFloat(p)
                    name(s.fromTitle, secondary: false).offset(x: x).opacity(SkipState.clamp(1 - 1.7 * p))
                    name(label, secondary: true).offset(x: x - finger * spacing).opacity(SkipState.clamp(1.7 * p - 0.7))
                }
            } else {
                MarqueeText(text: title, font: .system(size: fontSize, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func name(_ t: String, secondary: Bool) -> some View {
        Text(t).font(.system(size: fontSize, weight: secondary ? .medium : .semibold))
            .foregroundStyle(secondary ? Color.isletSecondary : Color.isletText)
            .lineLimit(1).truncationMode(.tail)
    }
}

/// Media swiped away, pointer over the notch. Without the glass look, a thin line under the camera glows in the album's
/// colours (with it, the glass strip itself is tinted: `GlassIsland`). A swipe sideways pulls the skip icon in from
/// that side as the peek deepens; the colour stays where it is and changes with the song.
struct MediaPeekView: View {
    let store: IslandStore
    var glass: Bool
    var height: CGFloat
    var notchHeight: CGFloat
    /// The glow line's length: 64 under the bare camera, longer along the bottom of quick info.
    var glowWidth: CGFloat = 64
    @State private var breathe = false

    var body: some View {
        let colors = store.peekColors
        ZStack(alignment: .top) {
            if !glass {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: glowWidth, height: 2)
                    .shadow(color: colors[colors.count / 2].opacity(0.7), radius: 4)
                    .saturation(1.2)
                    .brightness(breathe ? 0.08 : -0.18)
                    .padding(.top, height - 3.5)
                    .animation(.easeInOut(duration: 0.5), value: colors)
                    .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true } }
            }
            if let s = store.skip, s.dir != 0 {
                let p = SkipState.clamp(s.progress)
                // In from the side the new song comes from: the right for next, the left for previous.
                let x = CGFloat(s.dir) * 44 * (1 - (s.landedFade == nil ? p : 1))
                let depth = height - notchHeight - 6
                SkipIndicator(forward: s.dir == 1, size: 14, progress: s.landedFade == nil ? s.progress : 1,
                              armed: s.armed || s.landedFade != nil, pushes: s.pushes)
                    .opacity(s.landedFade.map { 1 - SkipState.clamp(($0 - 0.5) / 0.4) } ?? SkipState.clamp(p * 2.2))
                    .scaleEffect(0.6 + 0.4 * SkipState.clamp(p * 2))
                    .offset(x: x)
                    .padding(.top, notchHeight + max(0, depth) / 2 - 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity.animation(.easeOut(duration: 0.2)))
    }
}

/// Swiping hidden media back: the peek's colour gathers into the artwork's place in the wings or the chin, sharpening
/// into the cover as it goes. The real artwork shows once it's there.
struct PeekMorph: View {
    static let duration = 0.5
    let store: IslandStore
    var start: Date
    var glass: Bool
    /// The island's centre line and the notch.
    var centerX: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    /// Where the artwork lands, relative to the centre line and the top.
    var to: CGPoint
    var scale: CGFloat

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = min(max(ctx.date.timeIntervalSince(start) / Self.duration, 0), 1)
            // Ease out with a touch of overshoot, like the notch's own springs.
            let e = 1 + 2.2 * pow(t - 1, 3) + 1.2 * pow(t - 1, 2)
            let from = glass
                ? CGRect(x: -(notchWidth + 2) / 2, y: notchHeight + 1, width: notchWidth + 2, height: 5)
                : CGRect(x: -32, y: notchHeight + 1.5, width: 64, height: 2)
            let size = 22 * scale
            // The size eases in without overshoot (an overshoot would pinch the wide band thinner than the artwork);
            // only the position carries the springy settle.
            let es = 1 - pow(1 - t, 3)
            let w = from.width + (size - from.width) * es, h = from.height + (size - from.height) * es
            let cx = from.midX + (to.x * scale - from.midX) * e, cy = from.midY + (to.y * scale - from.midY) * e
            let r = min(w, h) / 2 + (6 * scale - min(w, h) / 2) * SkipState.clamp(t * 1.4)
            ZStack {
                LinearGradient(colors: store.peekColors, startPoint: .leading, endPoint: .trailing)
                if let art = store.media?.artwork {
                    Image(nsImage: art).resizable().scaledToFill().opacity(SkipState.clamp((t - 0.35) / 0.45))
                }
            }
            .frame(width: max(w, 1), height: max(h, 1))
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .blur(radius: (glass ? 2.5 : 0.8) * (1 - SkipState.clamp(t * 1.6)))
            .position(x: centerX + cx, y: cy)
        }
        .allowsHitTesting(false)
    }
}
