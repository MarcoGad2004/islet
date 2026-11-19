import SwiftUI

/// The island: one black shape that morphs between presentations. Content views arrive with each feature.
struct IslandView: View {
    let store: IslandStore

    /// Content fades in after the shape has mostly settled: 0.12 s for wings, 0.36 s for body shapes.
    private func fade(_ delay: Double = 0.36) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)).animation(.easeOut(duration: 0.3).delay(delay)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }

    var body: some View {
        let m = store.animator.metrics
        let pres = store.presentation
        let nh = store.geometry?.height ?? 34
        let content = store.content
        let key = "\(pres)-\(content?.kind ?? "-")"
        ZStack(alignment: .top) {
            IslandShape(m: m).fill(Color.black)
            // Content fades in once the shape has mostly settled (0.36 s) and out quickly (0.12 s).
            Group {
                switch pres {
                case .enrol:
                    if let e = store.enrolment {
                        EnrolView(model: e).frame(width: 380, height: 214).padding(.top, nh).transition(fade())
                    }
                case .scan:
                    if let s = store.scan {
                        ScanView(model: s).frame(width: store.geometry?.width ?? 190, height: 150).padding(.top, nh).transition(fade())
                    }
                case .expanded:
                    ExpandedView(store: store).padding(.top, nh).transition(fade())
                case .wings, .chin:
                    if let c = content {
                        CompactContentView(content: c, store: store, wings: pres == .wings).id(key).transition(fade(pres == .wings ? 0.12 : 0.36))
                    }
                case .peek, .closed:
                    if store.showsHiddenMediaDot {
                        Circle().fill(Color.isletGreen).frame(width: 4, height: 4)
                            .padding(.top, nh + 1).transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.3), value: key)
        }
        .clipShape(IslandShape(m: m))
        .contentShape(IslandShape(m: m))
        .onTapGesture { store.click() }
        .frame(width: NotchGeometry.panelWidth,
               height: store.geometry?.panelHeight ?? 300,
               alignment: .top)
    }
}
