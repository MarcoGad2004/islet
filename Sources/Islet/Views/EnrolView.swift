import SwiftUI

/// Face enrolment inside the island (owner's Option B, 2026-11-24): the line-drawn face inside one solid ring. The
/// ring's quarter for the direction to do next glows faintly, brighter while the head is turned that way, and fills
/// cyan once it's done; the face tilts with the head. On success the ring turns green and the face becomes a check.
struct EnrolView: View {
    let model: EnrolmentModel
    private let ringRadius: CGFloat = 58

    private var success: Bool { model.phase == .success }
    private var failed: Bool { if case .failed = model.phase { true } else { false } }

    var body: some View {
        let s = model.snapshot
        let scanning = model.phase == .scanning
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(failed ? Color.isletRed.opacity(0.5) : Color.isletRing, lineWidth: 4)
                    .frame(width: ringRadius * 2, height: ringRadius * 2)
                ForEach(0..<EnrolmentEngine.sectorCount, id: \.self) { q in
                    QuarterArc(sector: q, radius: ringRadius)
                        .stroke(arcColor(q, s, scanning: scanning), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .opacity(arcOpacity(q, s, scanning: scanning))
                        .animation(.easeInOut(duration: 0.3), value: arcOpacity(q, s, scanning: scanning))
                }
                FaceGlyph(color: success ? .isletGreen : failed ? .isletRed : s.faceVisible ? .isletCyan : Color(hex: 0x48484A),
                          size: 92, tilt: s.calibrated && scanning ? CGSize(width: s.x, height: s.y) : .zero, reach: 10,
                          breathing: scanning && !s.faceVisible, checked: success)
                    .modifier(ShakeEffect(shakes: failed ? 1 : 0))
                    .animation(.linear(duration: 0.45), value: failed)
            }
            .frame(width: 140, height: 140)

            Text(model.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(failed ? Color.isletRed : (success ? Color.isletGreen : Color.isletSecondary))
                .lineLimit(1).minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: model.label)
        }
        .padding(.top, 12)
    }

    /// The head is turned far enough towards sector `q` to capture it.
    private func reaching(_ q: Int, _ s: EnrolmentSnapshot) -> Bool {
        guard hypot(s.x, s.y) >= 1 else { return false }
        var angle = atan2(s.y, s.x)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle / (2 * .pi / Double(EnrolmentEngine.sectorCount))).rounded()) % EnrolmentEngine.sectorCount == q
    }

    private func arcColor(_ q: Int, _ s: EnrolmentSnapshot, scanning: Bool) -> Color {
        success ? .isletGreen : .isletCyan
    }

    private func arcOpacity(_ q: Int, _ s: EnrolmentSnapshot, scanning: Bool) -> Double {
        if success { return 1 }
        if failed { return 0 }
        if s.filled[q] { return 1 }
        guard scanning, s.calibrated, s.target == q else { return 0 }
        return reaching(q, s) ? 0.7 : 0.3
    }
}

/// A quarter of the ring, centred on sector `sector` (0 right, 1 up, 2 left, 3 down), with a gap either side.
private struct QuarterArc: Shape {
    let sector: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let centre = -Double(sector) * 90 // SwiftUI angles run clockwise from 3 o'clock; sectors run counter-clockwise
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: .degrees(centre - 40), endAngle: .degrees(centre + 40), clockwise: false)
        return p
    }
}
