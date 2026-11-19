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
    /// Closing into the notch runs in two legs: into a slightly swollen pill, then down to this.
    @ObservationIgnored private var then: IslandMetrics?
    /// For a wings close (no body to wait for): start the second leg once the width is this close to the pill's.
    @ObservationIgnored private var thenAtWidth: Double?

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

    /// Where the channels are heading.
    private var target: IslandMetrics {
        var t = metrics
        for i in 0..<IslandMetrics.channelCount { t[i] = channels[i].target }
        return t
    }

    func go(to target: IslandMetrics) {
        // Same destination (the pointer crossing the edge mid-morph, a refresh that changed nothing): leave the
        // running motion alone. Re-planning it would restart the delays and swap springs halfway through.
        if target == (then ?? self.target) { return }
        then = nil; thenAtWidth = nil
        var goal = target
        let current = metrics
        let growsBody = target.bh > current.bh + 0.5
        let shrinksBody = target.bh < current.bh - 0.5

        // Channel order: sw sh bw bh tr br ic
        let specs: [(Spring, Double)]
        let widthChange = target.sw - current.sw
        if current.bh > 40 && target.bh > 40 && abs(widthChange) < 2 && abs(target.bw - current.bw) < 2 {
            // The expanded panel changing height (Wi-Fi and Bluetooth lists): it bubbles to the new size, a soft
            // overshoot and settle, the same spring family as the hover bubble.
            let bubble = Spring(response: 0.46, damping: 0.55)
            specs = [(bubble, 0), (bubble, 0), (bubble, 0), (bubble, 0), (bubble, 0), (bubble, 0), (bubble, 0)]
        } else if (growsBody || shrinksBody) && abs(widthChange) > 40 {
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
        } else if shrinksBody && target.bh < 0.5 && current.bw > target.sw + 20 {
            // Chin or panel closing into the notch (DESIGN.md "Closing"). Like the iPhone's island it lands in a
            // pill a little bigger than the notch first: the stem swells while the body pulls in just ahead of
            // rising into it, so the body's corners stay round the whole way (tuned so they never dip below
            // 14 pt). When the body is gone, `tick` eases the pill down to the real notch.
            goal.sw = target.sw + 18
            goal.sh = target.sh + 6
            goal.bw = goal.sw
            goal.bh = 0
            goal.tr = 0
            goal.br = target.br + 4
            goal.ic = 0
            then = target
            let swell = Spring(response: 0.3, damping: 0.8)
            let inward = Spring(response: 0.18, damping: 1)
            let up = Spring(response: 0.26, damping: 1)
            specs = [(swell, 0), (swell, 0), (inward, 0), (up, 0.06), (inward, 0), (up, 0.06), (inward, 0)]
        } else if shrinksBody {
            // Reverse, as two separate steps so they never fight: the width pulls in to the notch's (settled by
            // 0.22 s), then the body rolls straight up behind the stem.
            let inward = Spring(response: 0.18, damping: 1)
            let up = Spring(response: 0.3, damping: 1)
            // Corner radii ride with the height (same delay and spring), so the shape stays rounded all the
            // way up instead of snapping boxy first. The inner curves shrink with the width.
            specs = [(inward, 0), (up, 0.22), (inward, 0), (up, 0.22), (up, 0.22), (up, 0.22), (inward, 0)]
        } else if widthChange < -40 && current.bh < 0.5 && target.bh < 0.5 {
            // Wings closing (a charge, media or an event ending): the same tuck as the chin. The wings pull in with
            // their momentum to a pill a touch bigger than the notch, which then eases down into it, instead of
            // stopping dead at the notch's edge.
            goal.sw = target.sw + 12
            goal.bw = goal.sw
            goal.sh = target.sh + 3
            goal.br = target.br + 3
            then = target
            thenAtWidth = goal.sw
            let inward = Spring(response: 0.3, damping: 0.86)
            let swell = Spring(response: 0.26, damping: 0.8)
            specs = [(inward, 0), (swell, 0), (inward, 0), (swell, 0), (swell, 0), (swell, 0), (swell, 0)]
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

        apply(goal, specs)
    }

    private func apply(_ goal: IslandMetrics, _ specs: [(Spring, Double)]) {
        for i in 0..<IslandMetrics.channelCount {
            channels[i].target = goal[i]
            channels[i].spring = specs[i].0
            // Delays stage a motion from rest. A channel that is already moving (hover bubble interrupted by the
            // chin, or the chin by the hover) turns toward the new target straight away with its momentum,
            // instead of freezing mid-air for the delay and then jumping on.
            let moving = abs(channels[i].velocity) > 1
            channels[i].delay = moving ? 0 : specs[i].1
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
        // Second leg of a close: once the body has been absorbed into the swollen pill, it eases down to the notch.
        let legDone = thenAtWidth.map { next.sw - $0 < 3 } ?? (next.bh < 2 && next.bw - next.sw < 1)
        if let final = then, legDone {
            then = nil; thenAtWidth = nil
            let settle = Spring(response: 0.38, damping: 0.9)
            apply(final, Array(repeating: (settle, 0), count: IslandMetrics.channelCount))
            moving = true
        }
        if !moving { timer?.invalidate(); timer = nil }
    }
}
