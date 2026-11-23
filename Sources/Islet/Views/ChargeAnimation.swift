import SwiftUI

/// The charging event's motion (DESIGN.md "Charging and battery", mockup docs/mockups/charging.html), timed from the
/// moment the event appears:
/// - 0.1 s: the number drifts up into place, growing from 80% and sharpening out of a slight blur (0.45 s).
/// - 0.15 to 0.85 s: it rolls from empty to the charge like an odometer and the battery fills with it; the roll starts
///   gently and eases out as it lands. Low battery starts full and rolls down, draining, in red.
/// - 0.45 s: the bolt springs in over the battery, settling at 0.85 s just as the fill stops (not for low battery).
/// - 0.85 s: the battery and the number both give a small springy bounce (about 6% bigger, then back).
struct ChargeTimeline {
    let event: ChargeEvent
    let t: Double

    static let rollStart = 0.15, rollLength = 0.7, boltStart = 0.45
    static var landing: Double { rollStart + rollLength }

    var from: Double { event.kind == .low ? 100 : 0 }
    var to: Double { event.kind == .full ? 100 : Double(event.percent) }

    /// The charge the number and fill show right now.
    var value: Double {
        let k = Self.soft(min(max((t - Self.rollStart) / Self.rollLength, 0), 1))
        return k >= 1 ? to : from + (to - from) * k
    }

    /// The number's arrival, 0 → 1.
    var intro: Double { Self.easeOut(min(max((t - 0.1) / 0.45, 0), 1)) }

    /// The bolt's scale (springing past 1 a little) and opacity; nil before it starts or with no bolt.
    var bolt: (scale: Double, opacity: Double)? {
        let b = t - Self.boltStart
        guard event.kind != .low, b > 0 else { return nil }
        return (Self.spring(b), min(b / 0.12, 1))
    }

    /// The landing bounce: a damped wave that swells to about 1.06 and settles back to 1 within half a second.
    var bounce: Double {
        let b = t - Self.landing
        guard b > 0 else { return 1 }
        return 1 + 0.13 * exp(-7 * b) * sin(12 * b)
    }

    var done: Bool { t > Self.landing + 0.8 }

    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    /// Eases in for the first quarter, then eases out.
    static func soft(_ x: Double) -> Double {
        x < 0.25 ? 4 * x * x : 0.25 + 0.75 * (1 - pow(1 - (x - 0.25) / 0.75, 2.4))
    }

    /// A gently underdamped spring (response 0.4 s, damping 0.62): about 8% past full size, settled in about 0.4 s.
    static func spring(_ t: Double) -> Double {
        let w = 2 * Double.pi / 0.4, z = 0.62, wd = w * (1 - z * z).squareRoot()
        return 1 - exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t))
    }
}

/// Drives a charge view from when it appears; with Reduce Motion it shows the end state.
private struct ChargeClock<Content: View>: View {
    let event: ChargeEvent
    @ViewBuilder let content: (ChargeTimeline) -> Content
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(ChargeTimeline(event: event, t: 10))
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: ChargeTimeline(event: event, t: Date().timeIntervalSince(start)).done)) { ctx in
                content(ChargeTimeline(event: event, t: ctx.date.timeIntervalSince(start)))
            }
        }
    }
}

/// The battery filling (or draining) with the bolt springing in on top, centred on the body.
struct ChargeBattery: View {
    let event: ChargeEvent

    var body: some View {
        ChargeClock(event: event) { tl in
            let h: CGFloat = 13
            BatteryBody(level: tl.value / 100, tint: event.kind == .low ? Color.isletRed : Color.isletGreen) {
                if let b = tl.bolt {
                    ChargeBolt().frame(width: 12, height: 17)
                        .scaleEffect(b.scale)
                        .rotationEffect(.degrees((1 - b.scale) * -12))
                        .opacity(b.opacity)
                }
            }
            .frame(width: BatteryMetrics.width(height: h), height: h)
            .scaleEffect(tl.bounce)
        }
    }
}

/// A heavy bolt, taller than the battery, white with a black outline so it reads over the fill and the empty part.
struct ChargeBolt: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 12, sy = size.height / 17
            let pts: [(Double, Double)] = [(7.6, 0.6), (1.2, 9.6), (5.5, 9.6), (4.1, 16.4), (10.8, 6.9), (6.4, 6.9), (8.3, 0.6)]
            var p = Path()
            p.addLines(pts.map { CGPoint(x: $0.0 * sx, y: $0.1 * sy) })
            p.closeSubpath()
            ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            ctx.fill(p, with: .color(.white))
        }
    }
}

/// The percentage rolling like an odometer: each digit is a column that scrolls, a higher one only moving while the
/// one below passes from 9 to 0, and digits fade out at the top and bottom as they pass. Leading columns open as the
/// number grows past 9 and 99.
struct ChargeNumber: View {
    let event: ChargeEvent
    var size: CGFloat = 13

    var body: some View {
        ChargeClock(event: event) { tl in
            let v = tl.value
            let n = tl.intro
            let hundreds = floor(v / 100) + clamp(v.truncatingRemainder(dividingBy: 100) - 99)
            let tens = floor(v / 10).truncatingRemainder(dividingBy: 10) + clamp(v.truncatingRemainder(dividingBy: 10) - 9)
            let ones = v.truncatingRemainder(dividingBy: 10)
            HStack(spacing: 0) {
                DigitColumn(position: hundreds, size: size).frame(width: digitWidth * clamp(v - 99), alignment: .trailing)
                DigitColumn(position: tens, size: size).frame(width: digitWidth * clamp(v - 9), alignment: .trailing)
                DigitColumn(position: ones, size: size).frame(width: digitWidth)
                Text("%").font(.system(size: size, weight: .semibold)).padding(.leading, 0.5)
            }
            .foregroundStyle(event.kind == .low ? Color.isletRedText : Color.isletGreen)
            .clipped()
            .opacity(n)
            .blur(radius: (1 - n) * 2.5)
            .scaleEffect(0.8 + 0.2 * n, anchor: .trailing)
            .offset(y: (1 - n) * 5)
            .scaleEffect(tl.bounce)
        }
    }

    private var digitWidth: CGFloat { size * 0.62 }
    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}

private struct DigitColumn: View {
    let position: Double
    let size: CGFloat

    var body: some View {
        let h = size * 1.7
        VStack(spacing: 0) {
            ForEach(0..<11, id: \.self) { i in
                Text("\(i % 10)").font(.system(size: size, weight: .semibold)).monospacedDigit().frame(height: h)
            }
        }
        .offset(y: -position * h)
        .frame(height: h, alignment: .top)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.24),
                                     .init(color: .black, location: 0.76), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
}
