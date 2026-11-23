import SwiftUI

/// Shazam in the notch (DESIGN.md "Shazam"). One stage that stays mounted from listening to the result, so its pieces
/// move instead of swapping: while listening, the Shazam glyph pulses in the left wing with ripples running out of it,
/// a little equaliser dances in the right wing and "Listening…" shimmers in the body (or all three sit in the chin).
/// On a match the island grows into a card, the glyph flies down into the artwork's place and grows into it, the cover
/// lands on it with a ring bursting out, and the title and artist slide in beside it. No match: the glyph shakes its
/// head and the bars lie down.
struct ShazamView: View {
    let store: IslandStore
    let state: ShazamState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var matchedAt: Date?
    @State private var shakes = 0

    static let blue = Color(hex: 0x0A84FF)
    static let canvas: CGFloat = 400
    private static let glyph: CGFloat = 22
    private static let art: CGFloat = 52

    private var song: ShazamSong? { state.song }
    private var wings: Bool { store.wingsFit && song == nil }
    private var failed: Bool {
        switch state.phase {
        case .failed, .micDenied: true
        default: false
        }
    }

    var body: some View {
        let nw = CGFloat(store.geometry?.width ?? 190), nh = CGFloat(store.geometry?.height ?? 34)
        let cx = Self.canvas / 2
        let l = layout(cx: cx, nw: nw, nh: nh)
        TimelineView(.animation(paused: !state.listening && matchedAt == nil)) { ctx in
            let t = ctx.date.timeIntervalSince(state.started)
            ZStack(alignment: .topLeading) {
                // Ripples out of the glyph while listening.
                if state.listening && !reduceMotion {
                    ForEach(0..<3, id: \.self) { i in
                        let p = (t / 1.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle().stroke(Self.blue.opacity((1 - p) * 0.55), lineWidth: 1.5)
                            .frame(width: Self.glyph + p * 30, height: Self.glyph + p * 30)
                            .position(l.glyph)
                    }
                }
                // The burst as the cover lands.
                if let m = matchedAt, !reduceMotion {
                    let p = min(max(ctx.date.timeIntervalSince(m) - 0.28, 0) / 0.6, 1)
                    RoundedRectangle(cornerRadius: 12 + p * 8, style: .continuous)
                        .stroke(Self.blue.opacity(p < 1 && p > 0 ? (1 - p) * 0.8 : 0), lineWidth: 2)
                        .frame(width: Self.art + p * 26, height: Self.art + p * 26)
                        .position(l.glyph)
                }

                glyph(t: t)
                    .position(l.glyph)

                if let song {
                    cover(song)
                        .position(l.glyph)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity)
                                .animation(.spring(response: 0.42, dampingFraction: 0.62).delay(0.26)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.isletText)
                        if !song.artist.isEmpty {
                            Text(song.artist).font(.system(size: 12)).foregroundStyle(Color.isletSecondary)
                        }
                    }
                    .lineLimit(1)
                    .frame(width: l.textWidth, alignment: .leading)
                    .position(l.text)
                    .transition(.asymmetric(
                        insertion: .offset(x: -14).combined(with: .opacity)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.32)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))))
                    Image(systemName: song.url == nil ? "shazam.logo" : "arrow.up.forward.app.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.isletTertiary)
                        .position(l.bars)
                        .transition(.opacity.animation(.easeOut(duration: 0.25).delay(0.45)))
                } else {
                    equaliser(t: t)
                        .position(l.bars)
                        .transition(.scale(scale: 0.2, anchor: .center).combined(with: .opacity).animation(.easeOut(duration: 0.18)))
                    line(t: t)
                        .frame(width: l.textWidth)
                        .position(l.text)
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                }
            }
            .frame(width: Self.canvas, height: nh + CGFloat(IslandLayout.shazamCardHeight) + 8, alignment: .topLeading)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: song)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: wings)
        .onChange(of: song) { _, s in
            matchedAt = s == nil ? nil : Date()
            // The burst is over in under a second; then the clock can stop.
            if s != nil { Task { try? await Task.sleep(for: .seconds(1)); matchedAt = nil } }
        }
        .onChange(of: state.phase) { _, p in if p == .noMatch || failed { shakes += 1 } }
        .frame(width: Self.canvas)
    }

    // MARK: Pieces

    /// The Shazam mark: the white S on blue. It breathes while listening, grows into the artwork's place on a match,
    /// greys out on no match.
    private func glyph(t: Double) -> some View {
        let size = song == nil ? Self.glyph : Self.art
        let beat = state.listening && !reduceMotion ? 1 + 0.07 * pow(sin(t * .pi * 2.2), 8) : 1
        let tint = song != nil || state.listening ? Self.blue : failed ? Color.isletRed : Color(hex: 0x636366)
        return Self.mark(size: size, tint: tint, square: song != nil)
        .scaleEffect(beat)
        .modifier(Shake(shakes: CGFloat(shakes)))
        .animation(.easeInOut(duration: 0.45), value: shakes)
        .animation(.easeOut(duration: 0.25), value: tint)
    }

    /// The Shazam mark. The symbol is a filled circle with the S cut out: over a white disc, in the tint, it reads as a
    /// white S on the tint. `square` is the artwork's rounded square.
    static func mark(size: CGFloat, tint: Color, square: Bool = false) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: square ? 12 : size / 2, style: .continuous).fill(tint)
            Circle().fill(.white).padding(size * (square ? 0.3 : 0.2))
            Image(systemName: "shazam.logo.fill").resizable().scaledToFit()
                .foregroundStyle(tint)
                .padding(square ? size * 0.14 : 0)
        }
        .frame(width: size, height: size)
    }

    /// Where the mark sits while listening, in the 400 pt canvas: the wing it was pulled in from (the left one from
    /// the button), or that end of the chin.
    static func markHome(fromRight: Bool, wings: Bool, nw: CGFloat, nh: CGFloat) -> CGPoint {
        let cx = canvas / 2, side: CGFloat = fromRight ? 1 : -1
        if wings { return CGPoint(x: cx + side * (nw / 2 + 30), y: nh / 2) }
        return CGPoint(x: cx + side * (CGFloat(IslandLayout.chinWidth) / 2 - 16 - glyph / 2), y: nh + CGFloat(IslandLayout.chinHeight) / 2)
    }

    private func cover(_ song: ShazamSong) -> some View {
        Group {
            if let art = song.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                // No cover: the glyph underneath stays as the art.
                Color.clear
            }
        }
        .frame(width: Self.art, height: Self.art)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Five bars dancing while listening; flat and grey once it has stopped without a song.
    private func equaliser(t: Double) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                let d = Double(i)
                let wave = 0.5 + 0.5 * sin(t * (5.1 + d * 1.7) + d * 1.3)
                let swell = 0.65 + 0.35 * sin(t * 1.4 + d * 0.9)
                let h: CGFloat = state.listening && !reduceMotion ? 4 + 12 * wave * swell : 3
                Capsule()
                    .fill(state.listening ? AnyShapeStyle(LinearGradient(colors: [Color.isletCyan, Self.blue], startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(Color(hex: 0x48484A)))
                    .frame(width: 3, height: h)
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.3), value: state.listening)
    }

    /// "Listening…" with a light sweeping across it, or what went wrong.
    @ViewBuilder private func line(t: Double) -> some View {
        let base = Text(state.text).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
        if state.listening && !reduceMotion {
            let x = (t / 1.8).truncatingRemainder(dividingBy: 1) * 1.6 - 0.3
            base.foregroundStyle(Color.isletSecondary)
                .overlay {
                    base.foregroundStyle(Color.isletText)
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: x - 0.25), .init(color: .white, location: x),
                                                   .init(color: .clear, location: x + 0.25)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                }
        } else {
            base.foregroundStyle(failed ? Color.isletRedText : Color.isletSecondary)
                .contentTransition(.opacity)
        }
    }

    // MARK: Layout

    private struct Layout { var glyph, text, bars: CGPoint; var textWidth: CGFloat }

    /// Where each piece sits: in the wings and the body, in the chin, or in the song's card.
    private func layout(cx: CGFloat, nw: CGFloat, nh: CGFloat) -> Layout {
        if song != nil {
            let w = CGFloat(IslandLayout.shazamCardWidth), h = CGFloat(IslandLayout.shazamCardHeight)
            let left = cx - w / 2 + 14
            let y = nh + h / 2 - 2
            let textX = left + Self.art + 12
            let textW = w - 14 - Self.art - 12 - 40
            return Layout(glyph: CGPoint(x: left + Self.art / 2, y: y), text: CGPoint(x: textX + textW / 2, y: y),
                          bars: CGPoint(x: cx + w / 2 - 24, y: y), textWidth: textW)
        }
        // The mark where it was pulled in; the equaliser mirrors it on the other side.
        let home = Self.markHome(fromRight: state.fromRight, wings: wings, nw: nw, nh: nh)
        let bars = CGPoint(x: 2 * cx - home.x, y: home.y)
        if wings {
            return Layout(glyph: home, text: CGPoint(x: cx, y: nh + IslandLayout.levelBodyHeight / 2 - 1),
                          bars: bars, textWidth: nw + CGFloat(IslandLayout.wingsExtra) - 2 * IslandLayout.levelSideInset)
        }
        let w = CGFloat(IslandLayout.chinWidth)
        return Layout(glyph: home, text: CGPoint(x: cx, y: home.y), bars: bars, textWidth: w - 2 * 16 - 2 * 30)
    }
}

/// A head shake: three quick swings that settle, once per increment.
private struct Shake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let f = shakes - shakes.rounded(.down)
        let x = 5 * sin(f * .pi * 6) * (1 - f)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

/// Two fingers dragging Shazam in over the idle notch (DESIGN.md "Shazam", "Pulling it in"). The mark rides in from
/// the edge the fingers came from, growing and filling in, with a ring round it that fills as it nears the commit
/// point. At the point the ring closes, the mark turns full blue and pops; past it, it keeps creeping in a little
/// against the band. Let go short of it and the spring carries it back out.
struct ShazamPullView: View {
    let pull: ShazamPull
    let home: CGPoint

    var body: some View {
        let r = CGFloat(pull.reach)
        let over = CGFloat(max(pull.progress - 0.5, 0))
        // -1: it comes in from the left (fingers moving right).
        let side: CGFloat = pull.dir == -1 ? 1 : -1
        let x = home.x + side * (1 - r) * 48 - side * over * 26
        let ease = r * r * (3 - 2 * r)
        ZStack {
            Circle().stroke(ShazamView.blue.opacity(0.22), lineWidth: 2).frame(width: 31, height: 31)
            Circle().trim(from: 0, to: r)
                .stroke(ShazamView.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 31, height: 31)
                .opacity(pull.armed ? 0 : 1)
            ShazamView.mark(size: 22, tint: pull.armed ? ShazamView.blue : ShazamView.blue.opacity(0.45 + 0.35 * ease))
        }
        .scaleEffect((0.5 + 0.5 * ease) * (pull.armed ? 1.08 : 1))
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: pull.armed)
        .opacity(min(1, r * 1.8))
        .blur(radius: (1 - r) * 2)
        .position(x: x, y: home.y)
        .frame(width: ShazamView.canvas, height: home.y * 2 + 40, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
