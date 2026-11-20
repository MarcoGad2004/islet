import Foundation
import QuartzCore

/// A two-finger swipe left or right over playing media (DESIGN.md "Skip and previous").
///
/// While the fingers are down, `progress` follows them directly: 0 is as it was, 1 is the neighbouring song fully
/// pulled in (`IslandStore.skipDistance` of finger travel). When they lift, a spring takes it from exactly there at
/// the fingers' speed, to 1 (the song changes) or back to 0.
struct SkipState: Equatable {
    enum Phase: Equatable {
        /// Following the fingers.
        case tracking
        /// Lifted; the spring is taking it to 1 (`landing`) or 0.
        case releasing(landing: Bool)
        /// Landed: the icon plays its push, the new name and artwork fade in. `fade` runs 0 to 1.
        case landed(fade: Double)
    }

    /// +1 next (fingers left), -1 previous (fingers right); 0 until the fingers pick a side.
    var dir = 0
    var progress = 0.0
    var phase = Phase.tracking
    /// The song's name when the swipe began: it rolls out while the incoming one rolls in.
    var fromTitle: String
    /// Counts landings, so the skip icon plays its push each time.
    var pushes = 0

    var armed: Bool { progress >= 0.5 }
    var landedFade: Double? { if case .landed(let f) = phase { f } else { nil } }

    /// How much the slot on the swipe's side has made way for the icon (the app icon for next, the artwork for
    /// previous): 0 untouched, 1 fully replaced. After landing it hands back.
    var slotTaken: Double {
        if let f = landedFade { return 1 - Self.clamp((f - 0.55) / 0.45) }
        return Self.clamp(progress * 2)
    }

    /// The skip icon's opacity in that slot.
    var iconOpacity: Double {
        if let f = landedFade { return 1 - Self.clamp((f - 0.55) / 0.45) }
        return Self.clamp(progress * 2 - 0.15)
    }

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}

/// A damped spring on one number, stepped at 120 Hz on the main run loop. Used for the skip swipe's release.
@MainActor
final class ValueSpring {
    private var x: Double, v: Double, target: Double
    private let k: Double, c: Double
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private let update: (Double) -> Void
    private let done: () -> Void

    /// `response` is the period in seconds; `damping` the damping ratio (1 = no overshoot).
    init(from: Double, to: Double, velocity: Double, response: Double, damping: Double,
         update: @escaping (Double) -> Void, done: @escaping () -> Void) {
        x = from; v = velocity; target = to
        let omega = 2 * Double.pi / response
        k = omega * omega; c = 2 * damping * omega
        self.update = update; self.done = done
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.05)
        last = now
        let steps = max(1, Int((dt / (1.0 / 480.0)).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            let a = -k * (x - target) - c * v
            v += a * h
            x += v * h
        }
        if abs(x - target) < 0.002 && abs(v) < 0.05 {
            stop()
            update(target)
            done()
            return
        }
        update(x)
    }
}

/// A plain clock over a duration (0 to 1), for the landing's fades.
@MainActor
final class Tween {
    private var timer: Timer?
    private let start = CACurrentMediaTime()
    private let duration: Double
    private let update: (Double) -> Void
    private let done: () -> Void

    init(duration: Double, update: @escaping (Double) -> Void, done: @escaping () -> Void) {
        self.duration = duration; self.update = update; self.done = done
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        let k = min((CACurrentMediaTime() - start) / duration, 1)
        update(k)
        if k >= 1 { stop(); done() }
    }
}
