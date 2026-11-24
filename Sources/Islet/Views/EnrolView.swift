import SwiftUI

/// Face enrolment inside the island: a ring of ticks in four parts (up, down, left, right), the next one lit faintly
/// and each turning cyan once it's done; a cyan dot follows the head, and the dot face shifts with it. On success the
/// dots fly into a check mark.
struct EnrolView: View {
    let model: EnrolmentModel
    private let ringRadius: CGFloat = 62

    private var success: Bool { model.phase == .success }
    private var failed: Bool { if case .failed = model.phase { true } else { false } }
    private var accent: Color { success ? .isletGreen : failed ? .isletRed : .isletCyan }

    var body: some View {
        let s = model.snapshot
        VStack(spacing: 8) {
            ZStack {
                ring(filled: s.filled, target: s.calibrated && model.phase == .scanning ? s.target : nil)
                FaceDots(shift: CGSize(width: s.x * 7, height: -s.y * 7).clamped(to: 12),
                         checked: success, showSweep: s.faceVisible && !failed)
                    .opacity(failed ? 0.35 : 1)
                if s.faceVisible && s.calibrated && model.phase == .scanning {
                    let v = vector(s)
                    Circle()
                        .fill(Color.isletCyan)
                        .frame(width: 8, height: 8)
                        .shadow(color: .isletCyan.opacity(0.8), radius: 5)
                        .offset(x: v.width, y: v.height)
                        .animation(.smooth(duration: 0.18), value: v)
                        .transition(.opacity)
                }
            }
            .frame(width: 140, height: 140)

            Text(model.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(failed ? Color.isletRed : (success ? Color.isletGreen : Color.isletSecondary))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: model.label)
        }
        .padding(.top, 12)
    }

    /// Head position inside the ring; it touches the ring at magnitude 1.
    private func vector(_ s: EnrolmentSnapshot) -> CGSize {
        let m = hypot(s.x, s.y)
        let k = m > 1.12 ? 1.12 / m : 1
        return CGSize(width: s.x * k * ringRadius, height: -s.y * k * ringRadius)
    }

    private func ring(filled: [Bool], target: Int?) -> some View {
        let per = 48 / EnrolmentEngine.sectorCount
        return ZStack {
            ForEach(0..<48, id: \.self) { i in
                let sector = i / per
                let on = filled[sector] || success
                let next = !on && sector == target
                // Sector 0 is centred on the right (3 o'clock) and they run counter-clockwise like the dot.
                let degrees = (Double(i) - Double(per - 1) / 2) / 48 * 360
                ZStack {
                    Capsule()
                        .fill(on ? accent : next ? Color.isletCyan.opacity(0.45) : Color.isletRing)
                        .frame(width: 2.4, height: on ? 10 : next ? 8.5 : 7)
                        .offset(y: -ringRadius)
                        .animation(.spring(response: 0.35, dampingFraction: 0.6).delay(Double(i % per) * 0.02), value: on)
                        .animation(.easeInOut(duration: 0.25), value: next)
                }
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(90 - degrees))
            }
        }
    }
}

private extension CGSize {
    func clamped(to limit: CGFloat) -> CGSize {
        let m = hypot(width, height)
        guard m > limit else { return self }
        return CGSize(width: width / m * limit, height: height / m * limit)
    }
}
