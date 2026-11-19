import AppKit

/// Single source of truth for what the island shows (ARCHITECTURE.md layer 5).
/// Modules publish events and state; priority is: face scan > unlock animation > volume/brightness >
/// charging/battery > media. Short events cover media and hand back when they end.
@MainActor @Observable
final class IslandStore {
    private(set) var geometry: NotchGeometry?
    /// Enrolment, the lock-screen scan and debug shapes. Enrol and scan override everything.
    private(set) var base: Presentation?
    private(set) var expanded = false
    private(set) var expandedPage = ExpandedPage.displaySound
    private(set) var pointerInside = false
    private(set) var paused = false

    // Content sources
    private(set) var charge: ChargeEvent?
    private(set) var level: LevelState?
    private(set) var unlockStart: Date?
    private(set) var media: MediaInfo?
    private(set) var mediaHidden = false
    private(set) var wingsFit = false
    var enrolment: EnrolmentModel?
    var scan: ScanModel?

    // Modules the expanded panel reads from.
    var power: PowerMonitor?
    var levels: LevelsController?
    var mediaMonitor: MediaMonitor?

    let animator = IslandAnimator()
    @ObservationIgnored var onExpandedChange: ((Bool) -> Void)?
    /// Decides wings vs chin (menu bar width check). nil or false means chin.
    @ObservationIgnored var layoutCheck: (() -> Bool)?
    @ObservationIgnored private var leaveTask: Task<Void, Never>?
    @ObservationIgnored private var chargeTask: Task<Void, Never>?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    @ObservationIgnored private var unlockTask: Task<Void, Never>?

    // MARK: Derived

    var mediaVisible: Bool { media != nil && !mediaHidden }

    var content: IslandContent? {
        if let unlockStart { return .unlock(start: unlockStart) }
        if let level { return .level(level) }
        if let charge { return .charge(charge) }
        if mediaVisible { return .media }
        return nil
    }

    private var compactLayout: Presentation { wingsFit ? .wings : .chin }

    var presentation: Presentation {
        // Enrolment and the face scan can't be interrupted by hover or clicks.
        if let b = base, b == .enrol || b == .scan { return b }
        if expanded { return .expanded }
        if let c = content {
            if case .level = c { return .chin } // volume and brightness always use the chin
            return compactLayout
        }
        if let base { return base }
        return pointerInside ? .peek : .closed
    }

    /// Green dot hint under the camera while media is hidden and the pointer is over the notch.
    var showsHiddenMediaDot: Bool { mediaHidden && media != nil && pointerInside && content == nil && !expanded && base == nil }

    // MARK: Geometry and layout

    func setGeometry(_ g: NotchGeometry?) {
        geometry = g
        recomputeLayout()
        if let m = targetMetrics() { animator.snap(to: m) }
    }

    /// Re-run the menu bar width check (app switch, event start, display change).
    func recomputeLayout() {
        let fits = layoutCheck?() ?? false
        guard fits != wingsFit else { return }
        wingsFit = fits
        refresh()
    }

    private func targetMetrics() -> IslandMetrics? {
        guard let g = geometry else { return nil }
        return presentation.metrics(notchWidth: g.width, notchHeight: g.height)
    }

    private func refresh() {
        if let m = targetMetrics() { animator.go(to: m) }
    }

    // MARK: Pointer and hit testing

    func isOverIsland(globalPoint: CGPoint) -> Bool {
        guard let g = geometry, !paused else { return false }
        let p = g.panelPoint(fromGlobal: globalPoint)
        let m = animator.metrics
        let slop = 2.0
        let rect = CGRect(x: NotchGeometry.panelWidth / 2 - m.width / 2 - slop, y: -slop,
                          width: m.width + 2 * slop, height: m.height + slop)
        return rect.contains(p)
    }

    func pointerMoved(inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            leaveTask?.cancel()
        } else if expanded {
            leaveTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.collapse()
            }
        }
        refresh()
    }

    // MARK: Actions

    private var locked: Bool { base == .enrol || base == .scan }

    /// Click: opens the panel (Display and Sound if a level bar was showing, else media if it is).
    func click() {
        expand()
    }

    func expand() {
        guard !expanded, !locked else { return }
        expandedPage = (level == nil && mediaVisible) ? .media : .displaySound
        levels?.refresh()
        power?.refresh()
        setExpanded(true)
    }

    func collapse() {
        guard expanded else { return }
        setExpanded(false)
    }

    private func setExpanded(_ value: Bool) {
        expanded = value
        leaveTask?.cancel()
        onExpandedChange?(value)
        refresh()
    }

    func swipeUp() {
        if expanded { collapse(); return }
        if mediaVisible && charge == nil && level == nil && unlockStart == nil {
            mediaHidden = true // stays hidden until swiped back or a different app starts playing
            refresh()
        }
    }

    func swipeDown() {
        if mediaHidden { mediaHidden = false; refresh(); return }
        expand()
    }

    func dismiss() { collapse() }

    func setBase(_ p: Presentation?) {
        base = p
        refresh()
    }

    func setPaused(_ value: Bool) {
        paused = value
        if value { expanded = false; pointerInside = false; base = nil; onExpandedChange?(false) }
        refresh()
    }

    // MARK: Content from modules

    func showCharge(_ event: ChargeEvent) {
        recomputeLayout()
        charge = event
        chargeTask?.cancel()
        chargeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(event.seconds))
            guard !Task.isCancelled else { return }
            self?.charge = nil
            self?.refresh()
        }
        refresh()
    }

    /// Volume and brightness hide 1.5 s after the last press.
    func showLevel(_ state: LevelState) {
        level = state
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.level = nil
            self?.refresh()
        }
        refresh()
    }

    /// The lock-opens animation, 1.8 s.
    func playUnlock() {
        recomputeLayout()
        unlockStart = Date()
        unlockTask?.cancel()
        unlockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.unlockStart = nil
            self?.refresh()
        }
        refresh()
    }

    func setMedia(_ info: MediaInfo?) {
        // A different app starting to play brings hidden media back.
        if let info, info.playing, media?.bundleID != info.bundleID || media?.playing == false, mediaHidden { mediaHidden = false }
        let appeared = (media == nil) != (info == nil)
        media = info
        if appeared { recomputeLayout() }
        refresh()
    }
}
