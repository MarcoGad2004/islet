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
    @State private var start = Date()

    /// Seconds resting at each end before it scrolls.
    private static let rest = 1.2

    var body: some View {
        GeometryReader { geo in
            let overflow = max(0, textWidth - geo.size.width)
            // Driven by the clock rather than a repeating animation: a never-ending animation inside a view keeps
            // SwiftUI from ever finishing its removal, which left the name behind under the notch after a swipe up.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: overflow <= 0)) { ctx in
                Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
                    .background(GeometryReader { p in Color.clear.preference(key: WidthKey.self, value: p.size.width) })
                    .offset(x: overflow > 0 ? Self.shift(overflow, at: ctx.date.timeIntervalSince(start)) : (geo.size.width - textWidth) / 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 18)
        .clipped()
        .onPreferenceChange(WidthKey.self) { textWidth = $0 }
        .onChange(of: text) { start = Date() }
        .id(text)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
    }

    /// Rest, scroll to the end (22 pt a second, plus half a second), rest, scroll back, and again.
    static func shift(_ overflow: CGFloat, at t: TimeInterval) -> CGFloat {
        let travel = Double(overflow) / 22 + 0.5
        let leg = rest + travel
        let p = t.truncatingRemainder(dividingBy: 2 * leg)
        let along: Double = p < rest ? 0 : p < leg ? (p - rest) / travel : p < leg + rest ? 1 : 1 - (p - leg - rest) / travel
        return -overflow * CGFloat(along)
    }
}

private struct WidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The 16-step bar (steps 9 x 6 pt, 3 pt gaps). The fill is one animatable value, so a change glides across the
/// steps on a spring instead of each step snapping on or off.
struct StepBar: View, Animatable {
    /// 0...1; the last lit step is partly filled between whole steps (fine adjustment).
    var value: Double
    var muted: Bool
    var stepWidth: CGFloat = 9
    /// Extended brightness past 100 (0...0.6): a second fill in red over the white one, from the left edge, on the
    /// same scale (0.6 fills to the 60 mark).
    var extra = 0.0
    /// The hold at 100 (0...1 of the whole bar) and how strongly it shows: a translucent red filling the bar.
    var charge = 0.0
    var chargeOpacity = 0.5

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(value, extra) }
        set { value = newValue.first; extra = newValue.second }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                let f = min(max(value * 16 - Double(i), 0), 1)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(muted ? Color.isletRing : Color(hex: 0x3A3A3C))
                    Rectangle().fill(muted ? Color(hex: 0x636366) : Color.isletText).frame(width: stepWidth * f)
                    Rectangle().fill(Color.isletRed.opacity(chargeOpacity)).frame(width: stepWidth * min(max(charge * 16 - Double(i), 0), 1))
                    Rectangle().fill(Color.isletRed).frame(width: stepWidth * min(max(extra * 16 - Double(i), 0), 1))
                }
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
                .frame(width: stepWidth, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: muted)
    }
}

/// The level's 16-step bar with extended brightness's cues at 100 (XDR Macs): reaching 100 the bar gives a little
/// bump, then the hint "Hold ☀ for XDR brightness" takes its place; holding the key fills the bar with translucent red
/// over a second; unlocking flashes it and collapses into the first red step.
struct LevelBar: View {
    let level: LevelState
    var stepWidth: CGFloat = 9
    @State private var hint = false
    @State private var bump = false

    private var cue: XDRCue? { level.kind == .brightness ? level.cue : nil }

    /// How far the hold has got, 0...1.
    static func progress(_ cue: XDRCue, at date: Date) -> Double {
        let t = date.timeIntervalSince(cue.since) - XDRCue.chargeDelay
        let p = min(max(t / (XDRCue.holdSeconds - XDRCue.chargeDelay), 0), 1)
        return p * p * (3 - 2 * p)
    }

    /// The red fill and its strength at a moment: growing while held, then a flash that fades as it unlocks.
    static func charge(_ cue: XDRCue?, at date: Date) -> (Double, Double) {
        guard let cue else { return (0, 0.5) }
        switch cue.kind {
        case .nudge: return (0, 0.5)
        case .charging: return (progress(cue, at: date), 0.35 + 0.25 * progress(cue, at: date))
        case .unlocked:
            let t = date.timeIntervalSince(cue.since)
            return (1, 0.85 * max(0, 1 - t / 0.55))
        }
    }

    var body: some View {
        let live = cue?.kind == .charging || cue?.kind == .unlocked
        TimelineView(.animation(paused: !live)) { ctx in
            let (c, o) = Self.charge(cue, at: ctx.date)
            StepBar(value: level.value, muted: level.muted, stepWidth: stepWidth, extra: level.extra, charge: c, chargeOpacity: o)
        }
        .animation(.levelGlide, value: level.value)
        .animation(.levelGlide, value: level.extra)
        // Let go too soon: the fill drains rather than vanishing.
        .animation(.easeOut(duration: 0.25), value: cue?.kind)
        .scaleEffect(x: bump ? 1.04 : 1, anchor: .leading)
        .opacity(hint ? 0 : 1)
        .overlay {
            if hint {
                XDRHint().transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .task(id: cue) {
            guard let cue, cue.kind == .nudge else {
                if hint { withAnimation(.easeOut(duration: 0.15)) { hint = false } }
                return
            }
            // Fresh at 100: a small push against the end, like reaching the end of a scroll.
            if Date().timeIntervalSince(cue.since) < 0.15 {
                withAnimation(.spring(response: 0.16, dampingFraction: 0.6)) { bump = true }
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { bump = false }
            }
            let wait = XDRCue.hintDelay - Date().timeIntervalSince(cue.since)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { hint = true }
        }
    }
}

/// The nudge at 100: "Hold ☀ for XDR brightness", in the bar's place.
struct XDRHint: View {
    var body: some View {
        (Text("Hold ") + Text(Image(systemName: "sun.max.fill")) + Text(" for ") + Text("XDR").foregroundColor(Color.isletRedText)
         + Text(" brightness"))
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText)
            .lineLimit(1).minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

/// The level's icon. Holding brightness-up at 100 it swells with a red glow; unlocking makes it bounce.
struct LevelIcon: View {
    let level: LevelState

    var body: some View {
        let cue = level.kind == .brightness ? level.cue : nil
        TimelineView(.animation(paused: cue?.kind != .charging)) { ctx in
            let p = cue.map { $0.kind == .charging ? LevelBar.progress($0, at: ctx.date) : 0 } ?? 0
            Image(systemName: level.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText)
                .scaleEffect(1 + 0.22 * p)
                .shadow(color: Color.isletRed.opacity(0.9 * p), radius: 5 * p)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: cue?.kind)
        .symbolEffect(.bounce, value: cue?.kind == .unlocked ? cue?.since : nil)
        .contentTransition(.symbolEffect(.replace)).animation(.levelGlide, value: level.symbol)
    }
}

/// The spring the level HUD uses for the bar and the rolling number.
extension Animation {
    static let levelGlide = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

/// A percentage whose digits roll up or down to the new value.
struct RollingNumber: View {
    var value: Double
    var off = false
    var suffix = ""
    var size: CGFloat = 13

    var body: some View {
        let n = Int((value * 100).rounded())
        Text(off ? "Off" : "\(n)\(suffix)")
            .font(.system(size: size, weight: .semibold)).monospacedDigit()
            .contentTransition(.numericText(value: off ? -1 : Double(n)))
            .animation(.levelGlide, value: n)
            .animation(.levelGlide, value: off)
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
    /// nil keeps the lock closed and white (the lock screen's resting state).
    var start: Date?
    var size: CGFloat = 0.9

    private func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { ctx in
            let t = start.map { ctx.date.timeIntervalSince($0) } ?? -1
            let dip = ease((t - 0.4) / 0.2)
            let lift = ease((t - 0.4) / 0.3)
            let swing = ease((t - 0.55) / 0.6)
            let green = ease((t - 0.8) / 0.2)
            ZStack {
                // Shackle: right leg is the hinge and stays seated in the body (it is 4.5 pt longer than it looks);
                // the shorter left leg is the free one. Opening lifts the shackle and swings the free leg up and out.
                Shackle()
                    .stroke(Color.isletText, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .overlay(Shackle().stroke(Color.isletGreen, style: StrokeStyle(lineWidth: 2.4, lineCap: .round)).opacity(green))
                    .frame(width: 11.5, height: 13.5)
                    .rotationEffect(.degrees(30 * swing), anchor: .bottomTrailing)
                    .offset(y: -2 - 3.5 * lift + dip)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.isletText)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.isletGreen).opacity(green))
                    .frame(width: 17, height: 12)
                    .offset(y: 6.3 + dip)
            }
            .frame(width: 26, height: 30) // headroom so the lifted shackle is never clipped
            .scaleEffect(size)
        }
    }
}

private struct Shackle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radius = r.width / 2
        // Left (free) leg is 4.5 pt shorter than the right (hinge) leg.
        p.move(to: CGPoint(x: r.minX, y: r.maxY - 4.5))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// A check mark of exact size (18 x 13 before the stroke), so its padding can be set precisely.
struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

struct CheckMark: View {
    var color: Color = .isletGreen
    var body: some View {
        CheckShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            .frame(width: 18, height: 13)
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
            CheckMark().scaleEffect(s)
        }
    }
}

/// An update's progress across all its steps (download, verify, install, restart). When it finishes, the bar fills
/// green and draws itself up into a round check at its right end; a failure does the same in red with a cross.
struct UpdateBar: View {
    var fraction: Double
    var done: Bool
    var failed: Bool
    var width: CGFloat

    var body: some View {
        let ended = done || failed
        let tint: Color = failed ? .isletRed : done ? .isletGreen : Color(hex: 0x0A84FF)
        ZStack(alignment: .leading) {
            Capsule().fill(Color(hex: 0x3A3A3C)).opacity(ended ? 0 : 1)
            Capsule().fill(tint).frame(width: ended ? 18 : max(6, width * min(max(fraction, 0), 1)))
        }
        .frame(width: ended ? 18 : width, height: ended ? 18 : 6)
        .overlay {
            Image(systemName: failed ? "xmark" : "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                .scaleEffect(ended ? 1 : 0.2).opacity(ended ? 1 : 0)
        }
        .frame(width: ended ? 18 : width, alignment: .trailing) // the check gives the text its room back
        .animation(.spring(response: 0.5, dampingFraction: 0.68), value: ended)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}
