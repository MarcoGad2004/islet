import SwiftUI

/// The island: one black shape that morphs between presentations. Content views arrive with each feature.
struct IslandView: View {
    let store: IslandStore
    @AppStorage(GlassLook.key) private var glassLook = true

    /// Content fades in after the shape has mostly settled: 0.12 s for wings, 0.36 s for body shapes.
    private func fade(_ delay: Double = 0.36) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)).animation(.easeOut(duration: 0.3).delay(delay)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }

    /// Wings content leaving: it draws in toward the notch with the wings as it fades, instead of vanishing in place
    /// while the shape is still moving.
    private func wingsFade(_ delay: Double) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)).animation(.easeOut(duration: 0.3).delay(delay)),
            removal: .opacity.combined(with: .scale(scale: 0.82)).animation(.easeIn(duration: 0.2)))
    }

    var body: some View {
        let m = store.animator.metrics
        let pres = store.presentation
        let nh = store.geometry?.height ?? 34
        let floating = store.geometry?.floating == true
        // Floating, the panel and enrolment start a small margin into the card instead of below the notch.
        let top = floating ? IslandLayout.floatingContentTop : nh
        let shape = floating ? AnyShape(CardShape(m: m)) : AnyShape(IslandShape(m: m))
        let content = store.content
        // Hovering something that's showing swells the shape; the content grows with it on the same spring, so its
        // padding stays even. (The dormant notch's peek has no content.)
        let swell = store.animator.hoverSwell
        let unswollen = max(m.sw - swell.sw, m.bw - swell.bw)
        let swellScale = unswollen > 1 ? m.width / unswollen : 1
        // Bezel mode's floating card keeps its black drop (its neck is drawn by thresholding black).
        let glass = glassLook && !floating
        // The hint's body grows and folds under the lock bar without remounting the padlock.
        // Media keeps its views from the wings into the hovered wide bar, so only the name below fades in.
        let mediaBar: Bool = if case .media? = content, pres == .levelWings { true } else { false }
        let key = store.base == .scan ? "scan" : "\(pres == .lockHint ? .lockWings : mediaBar ? .wings : pres)-\(content?.kind ?? "-")"
        ZStack(alignment: .top) {
            if floating { BezelBackdrop(m: m) }
            else if glass { GlassIsland(m: m, notchHeight: nh, tint: store.showsMediaPeek ? store.peekColors : nil) }
            else { IslandShape(m: m).fill(Color.black) }
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
                        EnrolView(model: e).frame(width: 380, height: 214).padding(.top, top).transition(fade())
                    }
                case .scan:
                    EmptyView()
                case .expanded:
                    ExpandedView(store: store).padding(.top, top)
                        .transition(fade())
                case .notification, .notificationTall:
                    if case .notification(let n)? = content {
                        NotificationCard(store: store, item: n, tall: pres == .notificationTall)
                            .id(pres).transition(fade())
                    }
                case .wings, .lockWings, .lockHint, .levelWings, .eventWings, .chin:
                    if let c = content {
                        CompactContentView(content: c, store: store, wings: pres != .chin, lockBar: pres == .lockWings || pres == .lockHint,
                                           levelBody: pres == .levelWings, hintBody: pres == .lockHint, eventBar: pres == .eventWings)
                            .id(key).transition(pres == .chin ? fade(0.36) : wingsFade(pres == .levelWings || pres == .lockHint ? 0.2 : 0.12))
                    }
                case .peek, .closed:
                    if floating && pres == .peek, let g = store.geometry {
                        // The orb: an arrow at the tip of the drop, for the swipe down.
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.isletTertiary)
                            .frame(width: 30, height: 30).padding(.top, g.floatTop)
                            .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.15)))
                    } else if store.showsMediaPeek {
                        MediaPeekView(store: store, glass: glass, height: m.height, notchHeight: nh)
                    }
                }
                }
            }
            .animation(.easeOut(duration: 0.3), value: key)
            .scaleEffect(swellScale, anchor: .top)
            // Floating, everything above sits at the card's top, wherever it is on its way.
            .offset(y: floating && pres != .peek ? m.y : 0)
            .frame(width: NotchGeometry.panelWidth, height: store.geometry?.panelHeight ?? 300, alignment: .top)
            .clipShape(shape)
            // Hidden media swiped back: the peek's colour gathers into the artwork.
            if let start = store.morphFromPeek, case .media? = content {
                let nw = store.geometry?.width ?? 190
                let to = pres == .chin ? CGPoint(x: -(IslandLayout.chinWidth / 2 - 16 - 11), y: nh + IslandLayout.chinHeight / 2)
                                       : CGPoint(x: -(nw / 2 + 30), y: nh / 2)
                PeekMorph(store: store, start: start, glass: glass, centerX: NotchGeometry.panelWidth / 2, notchWidth: nw,
                          notchHeight: nh, to: to, scale: swellScale)
                    .frame(width: NotchGeometry.panelWidth, height: store.geometry?.panelHeight ?? 300, alignment: .top)
                    .clipShape(shape)
            }
        }
        .environment(\.isletGlass, glass)
        .contentShape(shape)
        .onTapGesture { store.click() }
        .frame(width: NotchGeometry.panelWidth,
               height: store.geometry?.panelHeight ?? 300,
               alignment: .top)
    }
}
