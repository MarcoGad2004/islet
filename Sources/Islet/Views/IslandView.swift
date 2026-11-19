import SwiftUI

/// The island: one black shape that morphs between presentations. Content views arrive with each feature.
struct IslandView: View {
    let store: IslandStore

    var body: some View {
        let m = store.animator.metrics
        IslandShape(m: m)
            .fill(Color.black)
            .contentShape(IslandShape(m: m))
            .onTapGesture { store.click() }
            .frame(width: NotchGeometry.panelWidth,
                   height: store.geometry?.panelHeight ?? 300,
                   alignment: .top)
    }
}
