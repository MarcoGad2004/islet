import SwiftUI

/// Album artwork (or the placeholder) that cross-fades on track change and dims when paused.
struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var playing = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(hex: 0x5E5CE6))
            Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
                    .transition(.opacity)
                    .id(image.hash)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(playing ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.3), value: image?.hash)
        .animation(.easeOut(duration: 0.4), value: playing)
    }
}

/// 4 green bars bouncing on a ~1 s loop, easing flat and gray when paused.
struct LevelBars: View {
    var playing: Bool
    @State private var amp = 0.0

    static func barHeight(_ i: Int, time t: Double, amp: Double) -> CGFloat {
        let freq: Double = 1.0 + 0.13 * Double(i)
        let phase: Double = Double(i) * 1.7
        let wave: Double = (sin(t * 2 * Double.pi * freq + phase) + 1) / 2
        return CGFloat(5 + 9 * wave * amp)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing && amp == 0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(Color(white: 0.55).mix(with: .isletGreen, by: amp))
                        .frame(width: 2.5, height: LevelBars.barHeight(i, time: t, amp: amp))
                }
            }
            .frame(height: 14)
        }
        .onAppear { amp = playing ? 1 : 0 }
        .onChange(of: playing) { _, now in withAnimation(.easeOut(duration: 0.4)) { amp = now ? 1 : 0 } }
    }
}

/// Text that scrolls back and forth when it is wider than the space it has.
struct MarqueeText: View {
    var text: String
    var font: Font = .system(size: 13, weight: .semibold)
    var color: Color = .isletText
    @State private var textWidth: CGFloat = 0
    @State private var shift: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflow = max(0, textWidth - geo.size.width)
            Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
                .background(GeometryReader { p in Color.clear.preference(key: WidthKey.self, value: p.size.width) })
                .offset(x: overflow > 0 ? shift : (geo.size.width - textWidth) / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: overflow) { _, o in animate(o) }
                .onAppear { animate(overflow) }
        }
        .frame(height: 18)
        .clipped()
        .onPreferenceChange(WidthKey.self) { textWidth = $0 }
        .id(text)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
    }

    private func animate(_ overflow: CGFloat) {
        shift = 0
        guard overflow > 0 else { return }
        withAnimation(.linear(duration: Double(overflow) / 22 + 0.5).delay(1.2).repeatForever(autoreverses: true)) { shift = -overflow }
    }
}

private struct WidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The 16-step bar (steps 9 x 6 pt, 3 pt gaps).
struct StepBar: View {
    var steps: Int
    var muted: Bool
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < steps ? (muted ? Color(hex: 0x636366) : Color.isletText) : (muted ? Color.isletRing : Color(hex: 0x3A3A3C)))
                    .frame(width: 9, height: 6)
                    .animation(.easeOut(duration: 0.12), value: steps)
            }
        }
    }
}

private extension Color {
    func mix(with other: Color, by t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray, b = NSColor(other).usingColorSpace(.sRGB) ?? .green
        return Color(.sRGB, red: a.redComponent + (b.redComponent - a.redComponent) * t,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t)
    }
}

// MARK: - Padlock (lock opens)

/// DESIGN.md "Lock opens": closed white padlock; at 0.4 s the body dips ~1 pt, the shackle lifts ~2.5 pt and
/// swings open about its right leg (~28 deg, done by ~1.15 s); at 0.8 s it turns green.
struct PadlockView: View {
    var start: Date
    var size: CGFloat = 1

    private func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            let dip = ease((t - 0.4) / 0.2)
            let lift = ease((t - 0.4) / 0.3)
            let swing = ease((t - 0.55) / 0.6)
            let green = ease((t - 0.8) / 0.2)
            let color = Color.isletText.opacity(1 - green).opacity(1)
            ZStack {
                // Shackle: an inverted U anchored on its right leg.
                Shackle()
                    .stroke(Color.isletText, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .overlay(Shackle().stroke(Color.isletGreen, style: StrokeStyle(lineWidth: 2.2, lineCap: .round)).opacity(green))
                    .frame(width: 10, height: 8)
                    .rotationEffect(.degrees(-28 * swing), anchor: .bottomTrailing)
                    .offset(y: -8.5 - 2.5 * lift + dip)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.isletText)
                    .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color.isletGreen).opacity(green))
                    .frame(width: 14, height: 11)
                    .offset(y: dip)
            }
            .frame(width: 20, height: 26) // headroom so the lifted shackle is never clipped
            .scaleEffect(size)
            .foregroundStyle(color)
        }
    }
}

private struct Shackle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// Green check that pops in from scale 0 with overshoot (0.4 s).
struct CheckPop: View {
    var start: Date
    var delay: Double = 0.8
    var body: some View {
        TimelineView(.animation) { ctx in
            let x = min(max((ctx.date.timeIntervalSince(start) - delay) / 0.4, 0), 1)
            let c1 = 1.70158, c3 = c1 + 1
            let s = x == 0 ? 0 : 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2) // easeOutBack
            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.isletGreen).scaleEffect(s)
        }
    }
}
