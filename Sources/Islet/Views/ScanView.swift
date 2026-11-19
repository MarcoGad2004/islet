import SwiftUI

/// The face scan from DESIGN.md: dot grid inside a thin ring with a cyan sweep. A match flies the dots into a
/// green check; no match turns everything red and shakes the grid.
struct ScanView: View {
    let model: ScanModel

    private var matched: Bool { model.phase == .match }
    private var rejected: Bool {
        switch model.phase { case .noMatch, .failed: true; default: false }
    }
    private var tint: Color { matched ? .isletGreen : rejected ? .isletRed : .isletRing }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(tint, lineWidth: 1.5)
                FaceDots(scale: 1.35, checked: matched, showSweep: !matched && !rejected,
                         dotColor: rejected ? .isletRed : Color(hex: 0x48484A))
                    .modifier(ShakeEffect(shakes: CGFloat(model.shakes)))
            }
            .frame(width: 92, height: 92)
            .animation(.easeOut(duration: 0.25), value: model.phase)

            Text(model.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(matched ? Color.isletGreen : rejected ? Color(hex: 0xFF6961) : Color.isletSecondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: model.label)
        }
        .padding(.top, 10)
        .animation(.linear(duration: 0.45), value: model.shakes)
    }
}

/// Sideways shake: 0.45 s, three swings per bump of `shakes`.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(shakes * .pi * 6), y: 0))
    }
}
