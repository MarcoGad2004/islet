import Foundation
import QuartzCore

/// Drives the island metrics with one spring per dimension, so each part of the motion can have its own
/// timing (DESIGN.md "Flow down, then bubble out"). A single SwiftUI animation can't do that for one shape.
/// The timer only runs while something is moving, so an idle island costs nothing.
@MainActor @Observable
final class IslandAnimator {
    private(set) var metrics: IslandMetrics

    private struct Spring { var response: Double; var damping: Double }
    private struct Channel {
        var value = 0.0, velocity = 0.0, target = 0.0
        var spring = Spring(response: 0.3, damping: 1)
        var delay = 0.0
    }

    private var channels = [Channel](repeating: Channel(), count: IslandMetrics.channelCount)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick = CACurrentMediaTime()

    init(initial: IslandMetrics = IslandMetrics(sw: 190, sh: 34, bw: 190, bh: 0, tr: 0, br: 10, ic: 0)) {
        metrics = initial
        for i in 0..<IslandMetrics.channelCount { channels[i].value = initial[i]; channels[i].target = initial[i] }
    }

    /// Jump without animating (display changes).
    func snap(to target: IslandMetrics) {
        for i in 0..<IslandMetrics.channelCount {
            channels[i] = Channel(value: target[i], velocity: 0, target: target[i])
        }
        metrics = target
    }

    func go(to target: IslandMetrics) {
        let current = metrics
        let growsBody = target.bh > current.bh + 0.5
        let shrinksBody = target.bh < current.bh - 0.5

        // Channel order: sw sh bw bh tr br ic
        let specs: [(Spring, Double)]
        let widthChange = target.sw - current.sw
        if (growsBody || shrinksBody) && abs(widthChange) > 40 {
            // Wings <-> chin: one connected morph. The bar pinches in to the notch while the body drops out of
            // it (or the reverse), all on the same spring so nothing lags behind.
            let morph = Spring(response: 0.42, damping: 0.8)
            specs = [(morph, 0), (morph, 0), (morph, 0), (morph, 0), (morph, 0), (morph, 0), (morph, 0)]
        } else if growsBody {
            // Flow down first, bubble out sideways from 0.2 s, corners from 0.12 s, inner curves from 0.22 s.
            let down = Spring(response: 0.32, damping: 1)
            let out = Spring(response: 0.5, damping: 0.62)
            let corner = Spring(response: 0.35, damping: 1)
            specs = [(out, 0.2), (down, 0), (out, 0.2), (down, 0), (corner, 0.12), (corner, 0.12), (corner, 0.22)]
        } else if shrinksBody {
            // Reverse: width pulls in first, then the body slides up behind the stem from 0.18 s.
            let inward = Spring(response: 0.26, damping: 1)
            let up = Spring(response: 0.32, damping: 1)
            // Corner radii ride with the height (same delay and spring), so the shape stays rounded all the
            // way up instead of snapping boxy first. The inner curves shrink with the width.
            specs = [(inward, 0), (up, 0.18), (inward, 0), (up, 0.18), (up, 0.18), (up, 0.18), (inward, 0)]
        } else if widthChange > 40 {
            // Wings spring out with the soft overshoot (~0.55 s).
            let width = Spring(response: 0.5, damping: 0.62)
            let other = Spring(response: 0.35, damping: 0.9)
            specs = [(width, 0), (other, 0), (width, 0), (other, 0), (other, 0), (other, 0), (other, 0)]
        } else if widthChange > 2 || target.sh - current.sh > 2 {
            // Hover peek: a small, springy "bubble" up to the slightly larger shape.
            let bubble = Spring(response: 0.4, damping: 0.5)
            specs = [(bubble, 0), (bubble, 0), (bubble, 0), (bubble, 0), (bubble, 0), (bubble, 0), (bubble, 0)]
        } else {
            let settle = Spring(response: 0.3, damping: 0.9)
            specs = [(settle, 0), (settle, 0), (settle, 0), (settle, 0), (settle, 0), (settle, 0), (settle, 0)]
        }

        for i in 0..<IslandMetrics.channelCount {
            channels[i].target = target[i]
            channels[i].spring = specs[i].0
            channels[i].delay = specs[i].1
        }
        startTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        var moving = false
        var next = metrics

        for i in 0..<channels.count {
            var c = channels[i]
            var remaining = dt
            if c.delay > 0 {
                let used = min(c.delay, remaining)
                c.delay -= used
                remaining -= used
            }
            if c.delay > 0 { channels[i] = c; moving = true; continue }

            // Mass-spring-damper from response and damping fraction; fixed substeps for stability.
            let omega = 2 * Double.pi / c.spring.response
            let k = omega * omega
            let damp = 2 * c.spring.damping * omega
            let steps = max(1, Int((remaining / (1.0 / 480.0)).rounded(.up)))
            let h = remaining / Double(steps)
            for _ in 0..<steps {
                let a = -k * (c.value - c.target) - damp * c.velocity
                c.velocity += a * h
                c.value += c.velocity * h
            }
            if abs(c.value - c.target) < 0.01 && abs(c.velocity) < 0.05 {
                c.value = c.target; c.velocity = 0
            } else {
                moving = true
            }
            channels[i] = c
            next[i] = c.value
        }
        metrics = next
        if !moving { timer?.invalidate(); timer = nil }
    }
}
