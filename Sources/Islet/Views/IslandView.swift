import SwiftUI

/// The island: one black shape that morphs between presentations. Content views arrive with each feature.
struct IslandView: View {
    let store: IslandStore
    @AppStorage(GlassLook.key) private var glassLook = true
    /// Quick info's pieces and the panel's share it, so they glide from one to the other (DESIGN.md "Quick info").
    @Namespace private var quickInfo

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
            // The fade leads (gone in 0.1 s) so nothing is left over the glass strip or the desktop while the shape is
            // still pulling in past it (a song's name under the wide bar on a swipe up); the draw-in follows the wings.
            removal: AnyTransition.opacity.animation(.easeOut(duration: 0.1))
                .combined(with: AnyTransition.scale(scale: 0.82).animation(.easeIn(duration: 0.2))))
    }

    /// The level moving from the row under the unlock to its own place: one spring for every piece.
    static let glide = Animation.spring(response: 0.42, dampingFraction: 0.86)

    private func levelGlide(_ content: IslandContent?) -> Bool {
        guard store.levelLeftTray, case .level? = content else { return false }
        return true
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
        let searching = pres == .expanded && store.expandedPage == .search
        let key = store.base == .scan ? "scan" : "\(pres == .lockHint ? .lockWings : mediaBar ? .wings : pres)-\(content?.kind ?? "-")"
        ZStack(alignment: .top) {
            if floating { BezelBackdrop(m: m) }
            else if glass {
                GlassIsland(m: m, notchHeight: nh, tint: store.showsMediaPeek ? store.peekColors : nil,
                            smoke: searching ? 0.3 : GlassLook.smoke)
            }
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
                    if searching {
                        // Search brings in its own parts: the field early, the results as the shape settles.
                        SearchView(store: store, model: store.search, bodyWidth: m.bw).padding(.top, top)
                            .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12))))
                    } else {
                        // From quick info its pieces glide in, so the panel itself doesn't fade (the rest of it does).
                        ExpandedView(store: store).padding(.top, top)
                            .transition(store.expandedFromQuickInfo
                                        ? .asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12)))
                                        : fade())
                    }
                case .notification:
                    if case .notification(let n)? = content {
                        NotificationCard(store: store, item: n).transition(fade(0.2))
                    }
                case .wings, .lockWings, .lockHint, .levelWings, .eventWings, .chin:
                    if let c = content {
                        CompactContentView(content: c, store: store, wings: pres != .chin, lockBar: pres == .lockWings || pres == .lockHint,
                                           levelBody: pres == .levelWings, hintBody: pres == .lockHint, eventBar: pres == .eventWings)
                            .id(key).transition(levelGlide(content) ? .asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.1)))
                                                : pres == .chin ? fade(0.36) : wingsFade(pres == .levelWings || pres == .lockHint ? 0.2 : 0.12))
                    }
                case .earbuds:
                    if case .earbuds(let e)? = content {
                        EarbudsView(store: store, reading: e)
                            .transition(.opacity.animation(.easeOut(duration: 0.22).delay(0.1)))
                    }
                case .shazam:
                    if case .shazam(let s)? = content {
                        // Pulled in, the mark is already where it listens: nothing fades in.
                        ShazamView(store: store, state: s)
                            .transition(.asymmetric(
                                insertion: s.pulled ? .identity : .opacity.animation(.easeOut(duration: 0.22).delay(0.08)),
                                removal: .opacity.combined(with: .scale(scale: 0.85)).animation(.easeOut(duration: 0.14))))
                    }
                case .quickBar, .quickChin:
                    QuickInfoView(store: store, bar: pres == .quickBar)
                        // Shazam being pulled in pushes quick info out of the way.
                        .opacity(1 - (store.shazamPull?.reach ?? 0))
                        .blur(radius: 3 * (store.shazamPull?.reach ?? 0))
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(pres == .quickBar ? 0.06 : 0.12)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))))
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
            // Opening from quick info, the pieces glide on the shape's spring.
            .animation(store.expandedFromQuickInfo && pres == .expanded ? .spring(response: 0.5, dampingFraction: 0.82)
                       : levelGlide(content) ? Self.glide : .easeOut(duration: 0.3), value: key)
            .environment(\.quickInfoNamespace, quickInfo)
            .scaleEffect(swellScale, anchor: .top)
            // Floating, everything above sits at the card's top, wherever it is on its way.
            .offset(y: floating && pres != .peek ? m.y : 0)
            .frame(width: NotchGeometry.panelWidth, height: store.geometry?.panelHeight ?? 300, alignment: .top)
            // Two or more notifications: the next one tucked under, a strip just inside the deeper bottom edge.
            .overlay(alignment: .top) {
                let stacked: Bool = if case .notification? = content, store.notificationCount > 1, pres != .expanded { true } else { false }
                Capsule().fill(Color(hex: 0x3A3A3C))
                    .frame(width: max(m.width - 64, 0), height: 3)
                    .offset(y: m.y + m.height - 7)
                    .opacity(stacked ? 1 : 0)
                    .animation(.easeOut(duration: 0.2).delay(stacked ? 0.2 : 0), value: stacked)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                // The level row grown under the unlock, the lock bar or the scan.
                if let l = store.levelTray {
                    LevelTray(level: l, width: min(m.width, (store.geometry?.width ?? 190) + IslandLayout.wingsExtra), ns: quickInfo)
                        .offset(y: (floating ? m.y : 0) + m.height - IslandLayout.levelTrayHeight)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.12)),
                                                // Handing over to the level on its own, the pieces glide; the row
                                                // fades as they arrive.
                                                removal: store.level != nil ? .opacity.animation(.easeIn(duration: 0.3))
                                                                            : .opacity.animation(.easeOut(duration: 0.12))))
                        .allowsHitTesting(false)
                }
            }
            .animation(store.level != nil ? Self.glide : .easeOut(duration: 0.2), value: store.levelTray == nil)
            .overlay(alignment: .top) {
                // Shazam being dragged in from the side, ahead of the island it's making room in (clipped by it).
                if let pull = store.shazamPull, let g = store.geometry {
                    ShazamPullView(pull: pull, home: ShazamView.markHome(fromRight: pull.dir == -1, wings: store.wingsFit,
                                                                         nw: g.width, nh: g.height))
                        .offset(y: floating ? m.y : 0)
                }
            }
            .clipShape(shape)
            // Flush on the controls, the camera's own area opens Settings (no gear there).
            .overlay(alignment: .top) {
                if store.notchOpensSettings, let g = store.geometry {
                    Color.clear
                        .frame(width: g.width, height: g.height)
                        .contentShape(Rectangle())
                        .onHover { inside in withAnimation(.easeOut(duration: 0.2)) { store.settingsHover = inside } }
                        .onTapGesture {
                            store.settingsHover = false
                            store.collapse()
                            store.openSettings?()
                        }
                        .onDisappear { store.settingsHover = false }
                }
            }
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

/// Volume or brightness under whatever is showing: the icon, the step bar and the number, as in the wide bar.
private struct LevelTray: View {
    let level: LevelState
    let width: CGFloat
    var ns: Namespace.ID?

    var body: some View {
        let inset = IslandLayout.levelSideInset
        HStack(spacing: 10) {
            LevelIcon(level: level).frame(width: 18)
                .levelPiece("icon", ns)
            LevelBar(level: level, stepWidth: max(3, (width - 2 * inset - 18 - 30 - 20 - 15 * 3) / 16))
                .levelPiece("bar", ns)
            RollingNumber(value: level.shown, off: level.muted).foregroundStyle(Color.isletText)
                .frame(width: 30, alignment: .trailing)
                .levelPiece("number", ns)
        }
        .padding(.horizontal, inset)
        .frame(width: width, height: IslandLayout.levelTrayHeight - 6)
    }
}

