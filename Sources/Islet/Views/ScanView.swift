import SwiftUI

/// The face scan, in the wide notch expanded downward so the padlock stays visible in the right wing.
/// Dot grid inside a thin ring with a cyan sweep. A match flies the dots into a green check, the check then
/// flies to the left wing while the right-hand padlock opens. No match: red, with a shake.
struct ScanView: View {
    let model: ScanModel
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    private var matched: Bool { model.phase == .match }
    private var rejected: Bool {
        switch model.phase { case .noMatch, .failed: true; default: false }
    }
    private var tint: Color { matched ? .isletGreen : rejected ? .isletRed : .isletRing }

    private let ringSize: CGFloat = 92
    private let bodyTop: CGFloat = 10
    /// The wings row (the padlock) is drawn at full opacity from the first frame so it never blinks while the
    /// bar above it is swapped; only the ring and label below it fade in.
    @State private var bodyShown = false

    var body: some View {
        let nh = notchHeight, nw = notchWidth
        let barH = nh + IslandLayout.lockBarExtra
        // The ring's centre sits at (0, nh + bodyTop + ringSize/2) from the top centre; the landing spot is the
        // middle of the left wing.
        let fly = CGSize(width: -(nw / 2 + 30 + IslandLayout.checkInset), height: -(barH / 2 + bodyTop + ringSize / 2))
        ZStack(alignment: .top) {
            // Wings row: the padlock (closed until the match) on the right, the check's landing spot on the left.
            HStack(spacing: 0) {
                ZStack {
                    CheckMark()
                        .opacity(model.flown ? 1 : 0)
                        .scaleEffect(model.flown ? 1 : 0.5)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(model.flown ? 0.28 : 0), value: model.flown)
                }
                .offset(x: -IslandLayout.checkInset)
                .frame(width: 60, height: barH)
                Spacer().frame(width: nw)
                PadlockView(start: model.matchedAt?.addingTimeInterval(0.1))
                    .offset(x: IslandLayout.lockInset)
                    .frame(width: 60, height: barH)
            }

            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(tint, lineWidth: 1.5).opacity(model.flown ? 0 : 1)
                    FaceDots(scale: 1.35, checked: matched, showSweep: !matched && !rejected,
                             dotColor: rejected ? .isletRed : Color(hex: 0x48484A))
                        .modifier(ShakeEffect(shakes: CGFloat(model.shakes)))
                        .opacity(model.flown ? 0 : 1)
                        .animation(.easeIn(duration: 0.18).delay(model.flown ? 0.32 : 0), value: model.flown)
                }
                .frame(width: ringSize, height: ringSize)
                .scaleEffect(model.flown ? 0.43 : 1)
                .offset(model.flown ? fly : .zero)
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: model.flown)
                .animation(.easeOut(duration: 0.25), value: model.phase)

                Text(model.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .foregroundStyle(matched ? Color.isletGreen : rejected ? Color.isletRedText : Color.isletSecondary)
                    .contentTransition(.opacity)
                    .opacity(model.flown ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: model.label)
                    .animation(.easeOut(duration: 0.15), value: model.flown)
            }
            .padding(.top, barH + bodyTop)
            .opacity(bodyShown ? 1 : 0)
            .animation(.linear(duration: 0.45), value: model.shakes)
        }
        .frame(width: nw + IslandLayout.wingsExtra, height: barH + IslandLayout.scanHeight, alignment: .top)
        .onAppear { withAnimation(.easeOut(duration: 0.3).delay(0.12)) { bodyShown = true } }
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
