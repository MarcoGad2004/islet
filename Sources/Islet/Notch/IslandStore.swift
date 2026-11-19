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
    /// The open detail of the Control Center page. Wi-Fi and Bluetooth make the panel taller.
    private(set) var controlDetail: ControlDetail?
    private(set) var pointerInside = false
    private(set) var paused = false
    /// Set by the app; the gear in the expanded view calls it.
    @ObservationIgnored var openSettings: (() -> Void)?

    // Content sources
    private(set) var charge: ChargeEvent?
    private(set) var level: LevelState?
    private(set) var unlockStart: Date?
    private(set) var media: MediaInfo?
    private(set) var mediaHidden = false
    /// Media takes the notch only while it plays and for 30 s after a pause; the item itself is kept for the
    /// mini player in the expanded panel.
    private(set) var mediaFresh = false
    private(set) var wingsFit = false
    private(set) var eventWingsFit = false
    private(set) var event: IslandEvent?
    /// The Mac is locked with the screen on: the island shows the closed padlock in the wings.
    private(set) var lockScreen = false
    /// On the lock screen, the scan waits for Command+Shift: "⌘⇧" in the left wing, and now and then the wide bar
    /// grows a short body that spells it out (`lockHintFull`).
    private(set) var lockHint = false
    private(set) var lockHintFull = false
    var enrolment: EnrolmentModel?
    var scan: ScanModel?

    // Modules the expanded panel reads from.
    var power: PowerMonitor?
    var levels: LevelsController?
    var focus: FocusMonitor?
    var wifi: WiFiController?
    var bluetooth: BluetoothController?
    var display: DisplayToggles?
    var airdrop: AirDropController?
    var sidecar: SidecarController?
    var mediaMonitor: MediaMonitor?

    let animator = IslandAnimator()
    @ObservationIgnored var onExpandedChange: ((Bool) -> Void)?
    /// Decides wings vs chin (menu bar width check). nil or false means chin.
    @ObservationIgnored var layoutCheck: (() -> Bool)?
    @ObservationIgnored var eventLayoutCheck: (() -> Bool)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var leaveTask: Task<Void, Never>?
    @ObservationIgnored private var chargeTask: Task<Void, Never>?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    /// When the panel last opened or closed. Connection notices are passive: none while the panel is open or just
    /// after, when what connected is most likely what the user just picked there.
    @ObservationIgnored private var lastInUse = Date.distantPast
    static let quietAfterUse: TimeInterval = 6
    @ObservationIgnored private var unlockTask: Task<Void, Never>?
    @ObservationIgnored private var mediaStaleTask: Task<Void, Never>?
    @ObservationIgnored private var lockHintTask: Task<Void, Never>?

    // MARK: Derived

    var mediaVisible: Bool { media != nil && mediaFresh && !mediaHidden }
    /// The expanded panel shows the media page only for actively playing media.
    var mediaPlaying: Bool { media?.playing == true }

    /// 300 pt for the Wi-Fi and Bluetooth lists, 216 pt otherwise; the shape animates between them.
    var expandedBodyHeight: CGFloat {
        expandedPage == .displaySound && (controlDetail == .wifi || controlDetail == .bluetooth)
            ? IslandLayout.expandedListBodyHeight : IslandLayout.expandedBodyHeight
    }

    var content: IslandContent? {
        if let unlockStart { return .unlock(start: unlockStart) }
        if lockScreen { return .locked }
        if let level { return .level(level) }
        if let event { return .event(event) }
        if let charge { return .charge(charge) }
        if mediaVisible { return .media }
        return nil
    }

    private var compactLayout: Presentation { wingsFit ? .wings : .chin }

    var presentation: Presentation {
        // Enrolment and the face scan can't be interrupted by hover or clicks.
        if let b = base, b == .enrol || b == .scan {
            // Once the check starts flying, the scan folds up into the wide bar, which then holds the check
            // (left) and the opening padlock (right) for a moment.
            if b == .scan, scan?.flown == true { return .lockWings }
            return b
        }
        if expanded { return .expanded }
        if let c = content {
            if case .level = c { return wingsFit ? .levelWings : .chin } // wide bar with the step bar below when it fits
            if case .locked = c { return lockHint && lockHintFull ? .lockHint : .lockWings } // no menus here: always the wide bar
            if case .unlock = c { return wingsFit ? .lockWings : .chin }
            if case .event(let e) = c, e.kind == .hotspot { return wingsFit ? .levelWings : .chin } // the name goes in the body
            if case .event = c { return eventWingsFit ? .eventWings : .chin } // names need the wide bar or the chin
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
        let eventFits = eventLayoutCheck?() ?? false
        guard fits != wingsFit || eventFits != eventWingsFit else { return }
        wingsFit = fits
        eventWingsFit = eventFits
        refresh()
    }

    private func targetMetrics() -> IslandMetrics? {
        guard let g = geometry else { return nil }
        return presentation.metrics(notchWidth: g.width, notchHeight: g.height, bodyHeight: Double(expandedBodyHeight))
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
        expandedPage = (level == nil && mediaPlaying) ? .media : .displaySound
        levels?.refresh()
        power?.refresh()
        display?.refresh()
        airdrop?.refresh()
        bluetooth?.refresh()
        wifi?.refresh()
        focus?.retry()
        setExpanded(true)
    }

    func collapse() {
        guard expanded else { return }
        setExpanded(false)
    }

    private func setExpanded(_ value: Bool) {
        expanded = value
        lastInUse = Date()
        if value { eventTask?.cancel(); event = nil }
        controlDetail = nil
        leaveTask?.cancel()
        onExpandedChange?(value)
        refresh()
    }

    func swipeUp() {
        if expanded { collapse(); return }
        if mediaVisible && charge == nil && level == nil && event == nil && unlockStart == nil {
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

    /// Something that feeds `presentation` changed without a store property changing (the scan's phases).
    func presentationChanged() { refresh() }

    func setLockScreen(_ value: Bool) {
        guard value != lockScreen else { return }
        lockScreen = value
        refresh()
    }

    /// Shows the Command+Shift hint: "⌘⇧" in the wing at once, the full sentence after 1.5 s for 4 s, then
    /// every 12 s while it keeps waiting.
    func setLockHint(_ value: Bool) {
        guard value != lockHint else { return }
        lockHint = value
        lockHintFull = false
        lockHintTask?.cancel()
        if value {
            lockHintTask = Task { [weak self] in
                var wait = 1.5
                while true {
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled, let self else { return }
                    self.lockHintFull = true; self.refresh()
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    self.lockHintFull = false; self.refresh()
                    wait = 12
                }
            }
        }
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

    func showEvent(_ e: IslandEvent) {
        guard !expanded, Date().timeIntervalSince(lastInUse) > Self.quietAfterUse else { return }
        recomputeLayout()
        event = e
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(e.seconds))
            guard !Task.isCancelled else { return }
            self?.event = nil
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

    /// The lock-opens animation: 1.8 s once the content is in (plus its fade-in delay).
    func playUnlock() {
        recomputeLayout()
        unlockStart = Date()
        unlockTask?.cancel()
        unlockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.1))
            guard !Task.isCancelled else { return }
            self?.unlockStart = nil
            self?.refresh()
        }
        refresh()
    }

    func setMedia(_ info: MediaInfo?) {
        let wasPlaying = media?.playing == true
        // A different app starting to play brings hidden media back.
        if let info, info.playing, media?.bundleID != info.bundleID || !wasPlaying, mediaHidden { mediaHidden = false }
        let before = mediaVisible
        media = info
        mediaStaleTask?.cancel()
        if info?.playing == true {
            mediaFresh = true
        } else if wasPlaying && info != nil {
            // Just paused: keep it in the notch for 30 s, then hand the notch back.
            mediaFresh = true
            mediaStaleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.mediaFresh = false
                self?.recomputeLayout()
                self?.refresh()
            }
        } else if !wasPlaying {
            mediaFresh = false // paused at launch, or nothing: don't take the notch
        }
        if before != mediaVisible { recomputeLayout() }
        refresh()
    }

    /// From the mini player: open the full media page.
    func showMediaPage() { if expanded { controlDetail = nil; expandedPage = .media; refresh() } }
    func showControlsPage() { if expanded { expandedPage = .displaySound; refresh() } }

    func setControlDetail(_ d: ControlDetail?) {
        guard controlDetail != d else { return }
        controlDetail = d
        refresh()
    }
}
