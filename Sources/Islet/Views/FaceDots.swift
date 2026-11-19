import SwiftUI

/// The face-shaped dot grid from DESIGN.md "Face scan" (7x7 at 8 pt, within a 26 pt radius, ~33 dots),
/// which can fly into a check mark. Shared by enrolment and, later, the unlock scan.
struct FaceDots: View {
    var scale: CGFloat = 1.7
    /// Parallax shift in points (the face "follows" the head).
    var shift: CGSize = .zero
    var checked = false
    var showSweep = true

    private static let grid: [(row: Int, p: CGPoint)] = {
        var out: [(Int, CGPoint)] = []
        for iy in -3...3 { for ix in -3...3 where hypot(Double(ix) * 8, Double(iy) * 8) <= 26 {
            out.append((iy + 3, CGPoint(x: Double(ix) * 8, y: Double(iy) * 8)))
        } }
        return out
    }()

    /// Check-mark positions, spread along two strokes by arc length.
    private static let check: [CGPoint] = {
        let a = CGPoint(x: -20, y: 1), b = CGPoint(x: -8, y: 14), c = CGPoint(x: 22, y: -16)
        let l1 = hypot(b.x - a.x, b.y - a.y), l2 = hypot(c.x - b.x, c.y - b.y)
        let n = grid.count
        return (0..<n).map { i in
            let d = Double(i) / Double(n - 1) * (l1 + l2)
            if d <= l1 { let t = d / l1; return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
            let t = (d - l1) / l2
            return CGPoint(x: b.x + (c.x - b.x) * t, y: b.y + (c.y - b.y) * t)
        }
    }()

    var body: some View {
        TimelineView(.animation(paused: checked || !showSweep)) { context in
            let sweep = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3)) / 1.3 * 9 - 1
            ZStack {
                ForEach(Array(Self.grid.enumerated()), id: \.offset) { i, dot in
                    let target = checked ? Self.check[i] : CGPoint(x: dot.p.x * scale, y: dot.p.y * scale)
                    let near = showSweep && !checked && abs(Double(dot.row) - sweep) < 0.9
                    Circle()
                        .fill(checked ? Color.isletGreen : (near ? Color.isletCyan : Color(hex: 0x48484A)))
                        .frame(width: checked ? 4 : 3.2, height: checked ? 4 : 3.2)
                        .offset(x: target.x, y: target.y)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(checked ? Double(i) * 0.008 : 0), value: checked)
                }
            }
            .offset(checked ? .zero : shift)
        }
    }
}
