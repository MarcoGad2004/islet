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
        let key = store.base == .scan ? "scan" : "\(pres)-\(content?.kind ?? "-")"
        ZStack(alignment: .top) {
            IslandShape(m: m).fill(Color.black)
            // Content fades in once the shape has mostly settled (0.36 s) and out quickly (0.12 s).
            Group {
                if store.base == .scan, let scan = store.scan {
                    // Stays mounted through the fold into the wide bar (the shape changes, the content doesn't).
                    ScanView(model: scan, notchWidth: store.geometry?.width ?? 190, notchHeight: nh)
                        .zIndex(1)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12))))
                } else {
                switch pres {
                case .enrol:
                    if let e = store.enrolment {
                        EnrolView(model: e).frame(width: 380, height: 214).padding(.top, nh).transition(fade())
                    }
                case .scan:
                    EmptyView()
                case .expanded:
                    ExpandedView(store: store).padding(.top, nh)
                        .transition(fade())
                case .wings, .lockWings, .levelWings, .eventWings, .chin:
                    if let c = content {
                        CompactContentView(content: c, store: store, wings: pres != .chin, lockBar: pres == .lockWings, levelBody: pres == .levelWings, eventBar: pres == .eventWings)
                            .id(key).transition(fade(pres == .chin ? 0.36 : pres == .levelWings ? 0.2 : 0.12))
                    }
                case .peek, .closed:
                    if store.showsHiddenMediaDot {
                        Circle().fill(Color.isletGreen).frame(width: 4, height: 4)
                            .padding(.top, nh + 1).transition(.opacity)
                    }
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
