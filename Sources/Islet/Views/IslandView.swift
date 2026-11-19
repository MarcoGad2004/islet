import SwiftUI

/// The island: one black shape that morphs between presentations. Content views arrive with each feature.
struct IslandView: View {
    let store: IslandStore

    var body: some View {
        let m = store.animator.metrics
        let showEnrol = store.presentation == .enrol
        ZStack(alignment: .top) {
            IslandShape(m: m).fill(Color.black)
            // Content fades in once the shape has mostly settled (0.36 s) and out quickly (0.12 s).
            if showEnrol, let enrolment = store.enrolment {
                EnrolView(model: enrolment)
                    .frame(width: 380, height: 214)
                    .padding(.top, store.geometry?.height ?? 34)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)).animation(.easeOut(duration: 0.3).delay(0.36)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .animation(.easeOut(duration: 0.3), value: showEnrol)
        .clipShape(IslandShape(m: m))
        .contentShape(IslandShape(m: m))
        .onTapGesture { store.click() }
        .frame(width: NotchGeometry.panelWidth,
               height: store.geometry?.panelHeight ?? 300,
               alignment: .top)
    }
}
