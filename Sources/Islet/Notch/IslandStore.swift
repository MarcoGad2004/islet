import AppKit
import SwiftUI

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
    /// The app in front. Media from it stays out of the notch: you're already in the player.
    private(set) var frontBundleID: String?
    /// A two-finger swipe left or right over media: skip or previous, following the fingers (SkipGesture.swift).
    private(set) var skip: SkipState?
    @ObservationIgnored private var skipSpring: ValueSpring?
    @ObservationIgnored private var skipTween: Tween?
    /// Finger travel that pulls the neighbouring song half way in (the commit point). The pull resists more the
    /// further it goes, like stretching a band: progress = 1 - 1 / (1 + travel / skipDistance), so the content leads
    /// the fingers a little at first and trails them more and more toward the commit point; it never gets all the way
    /// in under the fingers (the landing spring does that).
    static let skipDistance: Double = 95
    /// Swiping hidden media back: the peek's colour gathers into the artwork (`PeekMorph`), so the real artwork
    /// waits until it has.
    private(set) var morphFromPeek: Date?
    @ObservationIgnored private var morphTask: Task<Void, Never>?
    private(set) var wingsFit = false
    private(set) var eventWingsFit = false
    private(set) var event: IslandEvent?
    /// Shazam listening or showing what it found (DESIGN.md "Shazam").
    private(set) var shazam: ShazamState?
    @ObservationIgnored private let shazamListener = ShazamListener()
    @ObservationIgnored private var shazamTask: Task<Void, Never>?
    /// Two fingers dragging Shazam in from the side over the idle notch (DESIGN.md "Shazam", "Pulling it in").
    private(set) var shazamPull: ShazamPull?
    @ObservationIgnored private var pullSpring: ValueSpring?
    /// Finger travel that pulls the mark half way, its commit point. Like the skip, the pull resists more the further
    /// it goes: progress = 1 - 1 / (1 + travel / shazamPullDistance).
    static let shazamPullDistance: Double = 85
    /// Two fingers up or down over Shazam listening: stopping it follows them (DESIGN.md "Shazam", "Stopping it").
    private(set) var shazamDrag: ShazamDrag?
    @ObservationIgnored private var dragSpring: ValueSpring?
    static let shazamDragDistance: Double = 60
    private(set) var progress: ConnectionProgress?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var progressAction: (() -> Void)?
    /// The Mac is locked with the screen on: the island shows the closed padlock in the wings.
    private(set) var lockScreen = false
    /// On the lock screen, the scan waits for Command+Shift: "⌘⇧" in the left wing, and now and then the wide bar
    /// grows a short body that spells it out (`lockHintFull`).
    private(set) var lockHint = false
    private(set) var lockHintFull = false
    /// Banners taken into the notch (DESIGN.md "Notifications"), newest first. They stack while they keep arriving and
    /// all go together 5 s after the last one (or from the list, one by one).
    /// whether a swipe down opened the taller card.
    private(set) var notifications: [NotificationItem] = []
    var notification: NotificationItem? { notifications.first }
    var notificationCount: Int { notifications.count }
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    /// The banner's own Show / Close, and the card running out (NotificationWatcher).
    @ObservationIgnored var notificationShow: ((NotificationItem) -> Void)?
    @ObservationIgnored var notificationClose: ((NotificationItem) -> Void)?
    @ObservationIgnored var notificationExpired: ((NotificationItem) -> Void)?
    /// One of the banner's own buttons (Approve, Deny, Remind Me…), by name.
    @ObservationIgnored var notificationAction: ((NotificationItem, String) -> Void)?
    static let notificationSeconds: Double = 5
    static let notificationAfterHover: Double = 3
    var enrolment: EnrolmentModel?
    var scan: ScanModel?

    // Modules the expanded panel reads from.
    var power: PowerMonitor?
    var levels: LevelsController?
    var updater: Updater?
    var focus: FocusMonitor?
    var wifi: WiFiController?
    var bluetooth: BluetoothController?
    var display: DisplayToggles?
    var airdrop: AirDropController?
    var sidecar: SidecarController?
    var mediaMonitor: MediaMonitor?
    var messages: MessagesStore?
    /// Search in the notch (DESIGN.md "Search").
    let search = SearchModel()
    /// The page the notification list was opened from (the pill), to go back to.
    @ObservationIgnored private var notificationReturnPage: ExpandedPage?
    /// The row of the notification list that's open: its whole message and its buttons (DESIGN.md "The list").
    private(set) var openNotificationID: UUID?
    /// Search took over the open panel (a letter typed there), so the shape is already out.
    private(set) var searchFromPanel = false
    /// Lists scrolling in the panel, where they are (top-left window points) and whether they're at either end
    /// (DESIGN.md "Gestures", "Over a list").
    func scrollRegion(at p: CGPoint) -> PanelScrollRegions.Region? {
        guard expanded else { return nil }
        return PanelScrollRegions.shared.region(at: p)
    }

    let animator = IslandAnimator()
    @ObservationIgnored var onExpandedChange: ((Bool) -> Void)?
    /// Decides wings vs chin (menu bar width check). nil or false means chin.
    @ObservationIgnored var layoutCheck: (() -> Bool)?
    @ObservationIgnored var eventLayoutCheck: (() -> Bool)?
    /// The menu bar has room for the panel itself (DESIGN.md "Flush panel").
    @ObservationIgnored var panelLayoutCheck: (() -> Bool)?
    /// The panel opened flush with the top, with no stem. Decided as it opens and kept until it opens again, so it
    /// never changes shape under the pointer.
    private(set) var flushPanel = false
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

    var mediaVisible: Bool { media != nil && mediaFresh && !mediaHidden && media?.bundleID != frontBundleID }
    /// The expanded panel shows the media page only for actively playing media.
    var mediaPlaying: Bool { media?.playing == true }

    /// 300 pt for the Wi-Fi and Bluetooth lists, 216 pt otherwise; the shape animates between them.
    var expandedBodyHeight: CGFloat {
        pageBodyHeight + (showsNotificationPill ? IslandLayout.notificationPillHeight : 0)
    }

    /// Flush, the controls' header row sits in the band beside the camera, so their page moves up by this much and
    /// the panel is that much shorter. Other pages keep their layout under the band.
    /// Flush, the pointer is behind the camera, which opens Settings when clicked: the controls' header row fades and
    /// "Click to open ⚙ Settings" shows on each side of it (DESIGN.md "Flush panel").
    var settingsHover = false

    /// Where the camera's area opens Settings: the panel is open flush on the controls (or one of their pages).
    var notchOpensSettings: Bool {
        expanded && flushLift > 0 && geometry?.mode == .notch
            && (expandedPage == .displaySound || expandedPage == .media)
    }

    var flushLift: CGFloat {
        guard flushPanel, [.media, .displaySound].contains(expandedPage), let g = geometry else { return 0 }
        return g.height / 2 + 29 // the header (26 tall, 16 below the band) centred in the band instead
    }

    /// Waiting notifications show as a pill at the top of the panel's own pages (DESIGN.md "Notifications", "In the panel").
    var showsNotificationPill: Bool {
        expanded && !notifications.isEmpty && [.media, .displaySound].contains(expandedPage)
    }

    /// The page itself, under the pill.
    var pageBodyHeight: CGFloat {
        if expandedPage == .notifications {
            return NotificationList.height(rows: notifications.count, open: notifications.first { $0.id == openNotificationID })
        }
        if expandedPage == .messages || expandedPage == .inbox { return IslandLayout.messagesBodyHeight }
        if expandedPage == .search { return search.bodyHeight }
        guard expandedPage == .displaySound else { return IslandLayout.expandedBodyHeight }
        switch controlDetail {
        case .wifi?, .bluetooth?: return IslandLayout.expandedListBodyHeight
        case .display? where levels?.keyboardAvailable == true: return IslandLayout.expandedDisplayBodyHeight
        case .battery?: return IslandLayout.expandedBatteryBodyHeight
        default: return IslandLayout.expandedBodyHeight
        }
    }

    /// Bezel mode (no notch): a card floating on screen can't stay up all the time, so the constant ones (music while
    /// it plays, the padlock while locked) are left out; only what comes and goes shows.
    private var floating: Bool { geometry?.floating == true }

    var content: IslandContent? {
        if let unlockStart { return .unlock(start: unlockStart) }
        if lockScreen && (!floating || (lockHint && lockHintFull)) { return .locked } // floating: only the ⌘⇧ reminder
        if let level { return .level(level) }
        if let notification { return .notification(notification) }
        if let shazam { return .shazam(shazam) }
        if let progress { return .progress(progress) }
        if let event { return .event(event) }
        if let charge { return .charge(charge) }
        if mediaVisible && !floating { return .media }
        return nil
    }

    private var compactLayout: Presentation { wingsFit ? .wings : .chin }

    /// Volume or brightness changed while something that outranks it is showing (the unlock, the lock screen, the
    /// face scan): instead of the change going unseen, the island grows a row under what's showing for the level
    /// (DESIGN.md "Volume and brightness").
    /// The level just left the row under the unlock (or the lock bar, or the scan) for a place of its own: its icon,
    /// bar and number glide across instead of fading out and back in.
    private(set) var levelLeftTray = false
    @ObservationIgnored private var hadTray = false

    var levelTray: LevelState? {
        guard let level, !expanded, !paused else { return nil }
        if base == .enrol { return nil }
        if base == .scan { return level }
        switch content {
        case .unlock?, .locked?: return level
        default: return nil
        }
    }

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
            if case .progress = c { return wingsFit ? .levelWings : .chin } // the step goes in the body
            if case .event(let e) = c, e.kind == .hotspot { return wingsFit ? .levelWings : .chin } // the name goes in the body
            if case .event = c { return eventWingsFit ? .eventWings : .chin } // names need the wide bar or the chin
            if case .shazam = c { return .shazam } // sized in targetMetrics: the bar, the chin, or the song's card
            // Hovered: the card. Otherwise the wide bar with the text in its body, or the chin.
            if case .notification = c { return pointerInside ? .notification : (wingsFit ? .levelWings : .chin) }
            // Media under the pointer (or mid-swipe): the wide bar, with the song's name in its body.
            if case .media = c, wingsFit, geometry?.mode == .notch, pointerInside || skip != nil { return .levelWings }
            return compactLayout
        }
        if let base { return base }
        if pointerInside, quickInfo { return wingsFit ? .quickBar : .quickChin }
        return pointerInside ? .peek : .closed
    }

    // MARK: Quick info (DESIGN.md "Quick info")

    static let quickInfoKey = "quickInfoOnHover"
    /// The pointer has rested on an idle notch: it shows the time, battery, Wi-Fi and Bluetooth.
    private(set) var quickInfo = false
    /// The panel opened from quick info: its pieces glide into their places instead of fading in.
    private(set) var expandedFromQuickInfo = false

    /// Nothing else would show under the pointer: no content, no hidden music's peek, the notch itself.
    private var quickInfoAllowed: Bool {
        guard UserDefaults.standard.object(forKey: Self.quickInfoKey) as? Bool ?? true else { return false }
        guard let g = geometry, g.mode == .notch, !paused, !expanded, base == nil, content == nil else { return false }
        return !(mediaHidden && media != nil && mediaFresh)
    }

    /// The pointer over an idle notch shows it at once, in place of the peek (owner, 2026-11-21: a quick peek).
    private func updateQuickInfo() {
        if pointerInside && quickInfoAllowed {
            guard !quickInfo else { return }
            wifi?.refresh(); bluetooth?.refresh()
            quickInfo = true
        } else if !pointerInside {
            quickInfo = false
        }
    }

    /// Media swiped away and the pointer over the notch: the peek takes the album's colours (DESIGN.md "Media peek").
    var showsMediaPeek: Bool {
        geometry?.mode == .notch && mediaHidden && media != nil && mediaFresh && pointerInside && content == nil
            && !expanded && base == nil
    }

    /// The peek's colours, from the artwork.
    var peekColors: [Color] { ArtworkPalette.colors(media?.artwork) }

    // MARK: Geometry and layout

    func setGeometry(_ g: NotchGeometry?) {
        geometry = g
        animator.floating = g?.floating == true
        recomputeLayout()
        if let m = targetMetrics() { animator.snap(to: m) }
    }

    /// Re-run the menu bar width check (app switch, event start, display change).
    func recomputeLayout(force: Bool = false) {
        let fits = layoutCheck?() ?? false
        let eventFits = eventLayoutCheck?() ?? false
        guard force || fits != wingsFit || eventFits != eventWingsFit else { return }
        wingsFit = fits
        eventWingsFit = eventFits
        if !force { refresh() }
    }

    private func targetMetrics() -> IslandMetrics? {
        guard let g = geometry else { return nil }
        var m = presentation.metrics(notchWidth: g.width, notchHeight: g.height, bodyHeight: Double(expandedBodyHeight))
        if presentation == .expanded, flushPanel {
            // No stem: the panel's own width from the top edge down, its top corners flaring into the edge.
            m.sw = IslandLayout.expandedWidth
            m.bw = m.sw
            m.bh = Double(expandedBodyHeight - flushLift)
            m.tr = 0
            m.ic = 0
        }
        if case .notification(let n)? = content, presentation != .expanded {
            // Two or more: a little deeper, for the one tucked under it. The card makes room for the banner's buttons.
            // The text decides the height, up to a limit: the island grows downward so it needn't be hovered to be read.
            switch presentation {
            case .notification: m.bh = Double(NotificationText.cardBody(n))
            case .levelWings: m.bh = Double(NotificationText.barBody(n, notchWidth: g.width))
            case .chin: m.bh = Double(NotificationText.chinBody(n, more: notifications.count >= 3))
            default: break
            }
            if notifications.count > 1 { m.bh += Double(IslandLayout.notificationStackDepth) }
            if presentation == .notification, notificationHasButtons(n) { m.bh += Double(IslandLayout.notificationActionsHeight) }
        }
        if case .shazam(let s)? = content, presentation == .shazam {
            typealias L = IslandLayout
            if s.song != nil {
                m = IslandMetrics(sw: Double(g.width), sh: Double(g.height), bw: L.shazamCardWidth, bh: L.shazamCardHeight, tr: 16, br: 22, ic: 10)
            } else if !wingsFit {
                m = Presentation.chin.metrics(notchWidth: g.width, notchHeight: g.height)
            }
        }
        if levelTray != nil {
            // At least the wide bar's width, so the level row has the room it has on its own.
            let w = Double(g.width) + IslandLayout.wingsExtra
            if m.sw >= m.bw { m.sw = max(m.sw, w); m.bw = m.sw } // the wide bar; the chin keeps its own width
            m.bh += Double(IslandLayout.levelTrayHeight)
            m.br = max(m.br, 18)
        }
        switch g.mode {
        case .notch: return m
        case .menuBar: return Self.underMenuBar(m, presentation)
        case .bezel: return Self.floating(m, presentation, floatTop: Double(g.floatTop))
        }
    }

    /// Bezel mode: a card as wide as its body floating `floatTop` down (10 pt under the menu bar), tucked above the
    /// top edge when idle, and the orb, a drop hanging from the edge down to that height, while the pointer is in the
    /// strip under the camera (`.peek`).
    static func floating(_ m: IslandMetrics, _ p: Presentation, floatTop: Double) -> IslandMetrics {
        switch p {
        case .closed: return IslandMetrics(sw: 46, sh: 22, bw: 46, bh: 0, tr: 0, br: 11, ic: 0, y: -40)
        case .peek: return IslandMetrics(sw: 30, sh: floatTop + 30, bw: 30, bh: 0, tr: 0, br: 15, ic: 0, y: 0)
        default:
            let w = max(m.sw, m.bw)
            // The panel and enrolment had the notch's height above their content; floating, a margin is enough.
            let top = p == .expanded || p == .enrol ? Double(IslandLayout.floatingContentTop) : m.sh
            let h = top + m.bh
            return IslandMetrics(sw: w, sh: top, bw: w, bh: m.bh, tr: 0, br: min(m.br, h / 2), ic: 0, y: floatTop)
        }
    }

    /// Without a notch there is nothing to hide the stem behind, so the island is a plain card hanging from the
    /// menu bar: as wide as its body, no inner curves, and nothing at all when idle (it grows out of the bar).
    static func underMenuBar(_ m: IslandMetrics, _ p: Presentation) -> IslandMetrics {
        if p == .closed || p == .peek { return IslandMetrics(sw: m.sw, sh: 0, bw: m.sw, bh: 0, tr: 0, br: 0, ic: 0) }
        let w = max(m.sw, m.bw)
        return IslandMetrics(sw: w, sh: m.sh, bw: w, bh: m.bh, tr: 0, br: m.br, ic: 0)
    }

    private func refresh() {
        updateQuickInfo()
        let tray = levelTray != nil
        if level == nil { if levelLeftTray { levelLeftTray = false } }
        else if hadTray && !tray { levelLeftTray = true }
        else if tray, levelLeftTray { levelLeftTray = false }
        hadTray = tray
        // Search's height follows the results without a bounce, and mid-opening only its target moves.
        if let m = targetMetrics() { animator.go(to: m, smoothHeight: expanded && expandedPage == .search) }
        animator.setSwell(hoverSwell)
    }

    /// With the pointer over something showing, the island swells a little (DESIGN.md "Hover"). It rides on top of
    /// the shape's own motion, so it answers straight away even mid-morph. The closed notch has its own peek shape,
    /// and the panel, scan and enrolment don't swell.
    private var hoverSwell: IslandMetrics {
        guard pointerInside, !paused, geometry?.mode == .notch else { return .zero }
        let w = IslandLayout.hoverSwellWidth, h = IslandLayout.hoverSwellHeight
        switch presentation {
        case .wings, .lockWings, .eventWings:
            return IslandMetrics(sw: w, sh: h, bw: w, bh: 0, tr: 0, br: 2, ic: 0)
        case .levelWings, .lockHint, .quickBar:
            return IslandMetrics(sw: w, sh: 0, bw: w, bh: h, tr: 0, br: 2, ic: 0)
        case .shazam:
            return wingsFit && shazam?.song == nil ? IslandMetrics(sw: w, sh: 0, bw: w, bh: h, tr: 0, br: 2, ic: 0)
                : IslandMetrics(sw: 0, sh: 0, bw: w + 2, bh: h + 1, tr: 0, br: 2, ic: 0)
        case .chin, .notification, .quickChin:
            return IslandMetrics(sw: 0, sh: 0, bw: w + 2, bh: h + 1, tr: 0, br: 2, ic: 0)
        default:
            return .zero
        }
    }

    // MARK: Pointer and hit testing

    func isOverIsland(globalPoint: CGPoint) -> Bool {
        guard let g = geometry, !paused else { return false }
        let p = g.panelPoint(fromGlobal: globalPoint)
        let m = animator.metrics
        let slop = 2.0
        if g.floating {
            // The card where it floats, or the hover strip in the middle of the menu bar, under the camera.
            let w = NotchGeometry.panelWidth
            let card = CGRect(x: w / 2 - m.width / 2 - slop, y: m.y - slop, width: m.width + 2 * slop, height: m.height + 2 * slop)
            let strip = CGRect(x: w / 2 - NotchGeometry.hoverStripWidth / 2, y: 0, width: NotchGeometry.hoverStripWidth, height: g.menuBarHeight)
            return (m.y > -1 && card.contains(p)) || (!expanded && strip.contains(p))
        }
        if g.virtual && m.height < 1 { return false } // nothing showing under the menu bar
        let rect = CGRect(x: NotchGeometry.panelWidth / 2 - m.width / 2 - slop, y: -slop,
                          width: m.width + 2 * slop, height: m.height + slop)
        return rect.contains(p)
    }

    func pointerMoved(inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        updateQuickInfo()
        if let s = shazam, !s.listening, !expanded {
            // Hovering the result keeps it; leaving gives it a little longer.
            if inside { shazamTask?.cancel() } else { armShazam(3) }
        }
        if !notifications.isEmpty, !expanded {
            // Hovering pauses them; leaving gives them a little longer.
            if inside { notificationTask?.cancel() } else { armNotification(Self.notificationAfterHover) }
        }
        if inside {
            leaveTask?.cancel()
        } else if expanded && expandedPage != .messages && expandedPage != .search {
            // Search is driven from the keyboard, and a conversation is being read and typed in (its right-click menu
            // and the emoji picker sit outside the panel): both stay when the pointer leaves.
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

    /// Click: opens the panel (Display and Sound if a level bar was showing, else media if it is). A result with a
    /// button (the update's "What's new") does that instead.
    func click() {
        if case .shazam? = content, !expanded { shazamClicked(); return }
        if let n = notification, !expanded {
            // A Messages one opens as its conversation; if it can't be found, in Messages as usual.
            openConversation(n) { [weak self] in self?.removeNotification(n, .shown) }
            return
        }
        if progress?.state == .done, let action = progressAction {
            progressTask?.cancel(); progress = nil; progressAction = nil
            refresh()
            action()
            return
        }
        expand()
    }

    func expand() {
        guard !expanded, !locked else { return }
        // From quick info, its pieces glide into the panel (DESIGN.md "Quick info").
        expandedFromQuickInfo = presentation == .quickBar || presentation == .quickChin
        // Always the panel's own page; waiting notifications ride along as a pill at its top.
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
        // The list closing: what's left stays in Notification Center.
        if !value, expandedPage == .notifications { endAllNotifications(.expired, refreshing: false) }
        if !value, expandedPage == .search { search.end() }
        if !value, expandedPage == .messages { messages?.close() }
        // Notifications left waiting under the pill show again briefly, then time out as usual.
        if !value, !notifications.isEmpty { armNotification(Self.notificationAfterHover) }
        if value { notificationTask?.cancel() }
        if value { flushPanel = geometry?.mode == .notch && panelLayoutCheck?() == true }
        if !value { notificationReturnPage = nil; openNotificationID = nil; expandedFromQuickInfo = false; quickInfo = false }
        expanded = value
        lastInUse = Date()
        if value { eventTask?.cancel(); event = nil }
        controlDetail = nil
        if !value { power?.watchDetails(false) }
        leaveTask?.cancel()
        onExpandedChange?(value)
        refresh()
    }

    // MARK: Search

    /// The search shortcut: opens search, or closes it when it's open.
    func toggleSearch() {
        if expanded && expandedPage == .search { collapse() } else { openSearch() }
    }

    /// Opens search, from the shortcut or with a letter typed in the open panel (DESIGN.md "Search", "From the panel").
    func openSearch(initial: String = "") {
        guard !locked, !paused, !lockScreen, geometry != nil else { return }
        search.close = { [weak self] in self?.collapse() }
        // A contact's Message: their conversation in the notch, when there is one.
        search.openConversation = { [weak self] handles, otherwise in
            guard let self, UserDefaults.standard.object(forKey: MessagesStore.enabledKey) as? Bool ?? true,
                  let m = self.messages, m.available, !handles.isEmpty else { return false }
            self.openChat(finding: { await m.findChat(forHandles: handles) }, otherwise: otherwise)
            return true
        }
        search.onChange = { [weak self] in
            guard let self, self.expanded, self.expandedPage == .search else { return }
            self.refresh()
        }
        if expanded {
            if expandedPage == .search { search.text = initial.isEmpty ? search.text : search.text + initial; return }
            if expandedPage == .messages { messages?.close() }
            if expandedPage == .notifications { endAllNotifications(.expired, refreshing: false) }
            searchFromPanel = true
            controlDetail = nil
            leaveTask?.cancel()
            search.begin(initial)
            expandedPage = .search
            onExpandedChange?(true) // the panel takes the keyboard
            refresh()
        } else {
            searchFromPanel = false
            search.begin(initial)
            expandedPage = .search
            setExpanded(true)
        }
    }

    /// The panel steps down under Emoji & Symbols while it's open (the island sits above nearly everything, the picker
    /// included). Set by the notch controller.
    @ObservationIgnored var onCharacterPalette: (() -> Void)?

    func showCharacterPalette() {
        NSApp.orderFrontCharacterPalette(nil)
        onCharacterPalette?()
    }

    /// A key pressed while the panel has the keyboard. True when it was used here and goes no further.
    func handleKey(_ key: KeyPress) -> Bool {
        guard expanded, !locked else { return false }
        // ⌃⌘Space: Emoji & Symbols, as in any app (Islet has no Edit menu to give it the shortcut).
        if key.control, key.command, key.code == KeyPress.space, expandedPage == .search {
            showCharacterPalette()
            return true
        }
        if expandedPage == .search { return searchKey(key) }
        // A letter typed in the open panel starts a search with it.
        if Feature.search.isOn, key.plainText, let c = key.characters, c != " " {
            openSearch(initial: c)
            return true
        }
        return false
    }

    private func searchKey(_ key: KeyPress) -> Bool {
        switch key.code {
        case KeyPress.down: if key.command { search.jumpSection(1) } else { search.move(1) }; return true
        case KeyPress.up: if key.command { search.jumpSection(-1) } else { search.move(-1) }; return true
        case KeyPress.left, KeyPress.right:
            // Along the recent apps; with text, the cursor in the field.
            guard search.isEmpty else { return false }
            search.move(key.code == KeyPress.right ? 1 : -1); return true
        case KeyPress.returnKey, KeyPress.enter: search.activate(reveal: key.command); return true
        case KeyPress.escape:
            if search.isEmpty { collapse() } else { search.text = "" }
            return true
        case KeyPress.tab: search.complete(); return true
        default: break
        }
        // No Edit menu in an agent app: the editing shortcuts go to the field by hand.
        if key.command, !key.control, let c = key.charactersIgnoringModifiers?.lowercased() {
            switch c {
            case "c" where !key.fieldHasSelection: return search.copySelected()
            case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            case "z": return NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            default: return false
            }
        }
        // Letters typed before the field has the cursor are kept here, in order (DESIGN.md "Typing while it opens").
        if !search.fieldReady {
            if key.code == KeyPress.delete { if !search.text.isEmpty { search.text.removeLast() }; return true }
            if key.plainText, let c = key.characters { search.text += c; return true }
        }
        return false
    }

    /// With the panel open, a swipe up closes it only from the notch itself (top-left window points), where nothing is
    /// ever drawn; anywhere else in the panel the fingers scroll what's under them. Without a notch, from the panel's
    /// top strip. Closed, the whole island takes it as before.
    func swipeUpAllowed(at p: CGPoint) -> Bool {
        guard expanded, let g = geometry else { return true }
        let center = NotchGeometry.panelWidth / 2
        if g.mode == .notch {
            return abs(p.x - center) <= g.width / 2 + 6 && p.y <= g.height + 4
        }
        return p.y <= (g.floating ? g.floatTop : 0) + IslandLayout.floatingContentTop
    }

    func swipeUp() {
        if skip != nil { return }
        if case .shazam? = content, !expanded { endShazam(); return }
        if !notifications.isEmpty, !expanded { endAllNotifications(.closed); return }
        if expanded { collapse(); return }
        if mediaVisible && charge == nil && level == nil && event == nil && unlockStart == nil {
            mediaHidden = true // stays hidden until swiped back or a different app starts playing
            refresh()
        }
    }

    func swipeDown() {
        if skip != nil { return }
        if !notifications.isEmpty, !expanded {
            // The list of everything that just came in; it stays while it's in use.
            notificationTask?.cancel()
            expand()
            return
        }
        if mediaHidden {
            // From the peek, its colour gathers into the artwork as media comes back.
            if showsMediaPeek {
                morphFromPeek = Date()
                morphTask?.cancel()
                morphTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(PeekMorph.duration))
                    guard !Task.isCancelled else { return }
                    self?.morphFromPeek = nil
                }
            }
            mediaHidden = false; refresh(); return
        }
        expand()
    }

    // MARK: Skip and previous

    /// The fingers started sideways over the island. Only playing media (showing, or hidden behind the peek) skips.
    func skipBegan() -> Bool {
        if shazamPullAllowed {
            pullSpring?.stop(); pullSpring = nil
            shazamPull = ShazamPull()
            return true
        }
        guard !expanded, base == nil, !paused, let m = media, mediaMonitor != nil else { return false }
        let onMedia: Bool = if case .media? = content { true } else { false }
        guard onMedia || showsMediaPeek else { return false }
        finishSkipNow()
        skip = SkipState(fromTitle: m.artist.isEmpty ? m.title : "\(m.title) · \(m.artist)")
        refresh()
        return true
    }

    /// Finger travel since the swipe began, in points: negative is left (next), positive right (previous).
    func skipChanged(_ dx: Double) {
        if shazamPull != nil { shazamPullChanged(dx); return }
        guard var s = skip, case .tracking = s.phase else { return }
        if dx < 0 { s.dir = 1 } else if dx > 0 { s.dir = -1 }
        let wasArmed = s.armed
        s.progress = 1 - 1 / (1 + abs(dx) / Self.skipDistance)
        // A light tap on the trackpad as it crosses half way, either way.
        if s.armed != wasArmed { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        skip = s
        updateSkipDepth()
    }

    /// The fingers lifted, moving at `velocity` (points per second, positive right). The spring starts from where
    /// they left it at their speed: past half way, or flung in, the neighbour lands and the song changes now.
    func skipEnded(velocity: Double) {
        if shazamPull != nil { shazamPullEnded(velocity: velocity); return }
        guard var s = skip, case .tracking = s.phase else { return }
        guard s.dir != 0 else { skip = nil; refresh(); return }
        // Progress per second (+ is further in): the fingers' speed through the pull's resistance at this point.
        let pv = (s.dir == 1 ? -velocity : velocity) * (1 - s.progress) * (1 - s.progress) / Self.skipDistance
        // Only past the line counts (the ring around the icon is full and it has turned solid), however fast the
        // fingers were going; throwing it back out from past the line cancels.
        let land = s.armed && pv > -2
        if land { s.dir == 1 ? mediaMonitor?.next() : mediaMonitor?.previous() }
        s.phase = .releasing(landing: land)
        skip = s
        let response = land ? min(max(0.34 - abs(pv) * 0.012, 0.18), 0.34) : 0.3
        skipSpring?.stop()
        skipSpring = ValueSpring(from: s.progress, to: land ? 1 : 0, velocity: pv, response: response,
                                 damping: land ? 0.8 : 0.7, // back out with a little elastic snap
                                 update: { [weak self] p in self?.skip?.progress = p; self?.updateSkipDepth() },
                                 done: { [weak self] in land ? self?.skipLanded() : self?.clearSkip() })
    }

    /// The neighbour is in: the icon pushes, then the real name and artwork take over and the slot hands back.
    private func skipLanded() {
        guard var s = skip else { return }
        s.pushes += 1
        s.phase = .landed(fade: 0)
        skip = s
        skipTween?.stop()
        skipTween = Tween(duration: 0.6, update: { [weak self] k in
            guard let self, var s = self.skip, case .landed = s.phase else { return }
            s.phase = .landed(fade: k)
            self.skip = s
            self.updateSkipDepth()
        }, done: { [weak self] in self?.clearSkip() })
    }

    private func clearSkip() {
        skipSpring?.stop(); skipSpring = nil
        skipTween?.stop(); skipTween = nil
        skip = nil
        animator.setExtra(.zero)
        refresh()
    }

    /// A new swipe while the last one is still settling: jump to its end.
    private func finishSkipNow() { if skip != nil { clearSkip() } }

    /// On the peek, the shape deepens with the swipe to make room for the icon, and eases back after landing.
    private func updateSkipDepth() {
        guard let s = skip, presentation == .peek else { animator.setExtra(.zero); return }
        var depth = 18 * SkipState.clamp(s.progress * 1.6)
        if let f = s.landedFade { depth *= 1 - f * f * (3 - 2 * f) }
        animator.setExtra(IslandMetrics(sw: 0, sh: depth, bw: 0, bh: 0, tr: 0, br: 0, ic: 0))
    }


    // MARK: Shazam (DESIGN.md "Shazam")

    /// Two fingers sideways over the idle notch (quick info, the peek) drag Shazam in. Media takes the swipe for
    /// skipping first.
    private var shazamPullAllowed: Bool {
        guard Feature.shazam.isOn, pointerInside, !expanded, base == nil, !paused, !lockScreen, skip == nil else { return false }
        return content == nil && !showsMediaPeek
    }

    /// The mark follows the fingers in from the side they started toward, against a rubber band. The trackpad ticks
    /// lightly as it catches, clicks firmly crossing the commit point (it's in), and ticks lightly going back over it.
    private func shazamPullChanged(_ dx: Double) {
        guard var p = shazamPull, !p.releasing else { return }
        if dx > 0 { p.dir = 1 } else if dx < 0 { p.dir = -1 }
        let wasArmed = p.armed
        p.progress = 1 - 1 / (1 + abs(dx) / Self.shazamPullDistance)
        if !p.caught, p.progress > 0.1 {
            p.caught = true
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        if p.armed != wasArmed {
            NSHapticFeedbackManager.defaultPerformer.perform(p.armed ? .levelChange : .alignment, performanceTime: .now)
        }
        shazamPull = p
        updatePullShape()
    }

    /// Let go past the commit point (and not flung back out): it listens. Short of it: the mark springs back out the
    /// way it came, at the fingers' speed, with a little elastic snap, and nothing runs.
    private func shazamPullEnded(velocity: Double) {
        guard var p = shazamPull, !p.releasing else { return }
        guard p.dir != 0 else { shazamPull = nil; updatePullShape(); refresh(); return }
        // Progress per second (+ further in), through the band's resistance at this point.
        let pv = (p.dir == 1 ? velocity : -velocity) * (1 - p.progress) * (1 - p.progress) / Self.shazamPullDistance
        if p.armed && pv > -2 {
            shazamPull = nil
            animator.setExtra(.zero)
            // The landing: a tap with the mark's bounce (felt while a finger is still on the trackpad).
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            startShazam(fromRight: p.dir == -1, pulled: true)
            return
        }
        p.releasing = true
        shazamPull = p
        pullSpring?.stop()
        pullSpring = ValueSpring(from: p.progress, to: 0, velocity: pv, response: 0.34, damping: 0.66,
                                 update: { [weak self] x in self?.shazamPull?.progress = max(x, 0); self?.updatePullShape() },
                                 done: { [weak self] in
                                     self?.pullSpring = nil
                                     self?.shazamPull = nil
                                     self?.updatePullShape()
                                     self?.refresh()
                                 })
    }

    /// The island makes room for the mark as it comes in: the closed notch grows its wings (or a chin when the menu bar
    /// has no room); quick info, which already has them, stretches a little with the pull.
    private func updatePullShape() {
        guard let p = shazamPull else { animator.setExtra(.zero); return }
        let r = p.reach, over = max(p.progress - 0.5, 0)
        switch presentation {
        case .quickBar, .quickChin:
            let w = 10 * r + 24 * over
            animator.setExtra(IslandMetrics(sw: w, sh: 0, bw: w, bh: 0, tr: 0, br: 0, ic: 0))
        case .peek, .closed:
            guard let g = geometry else { return }
            if wingsFit {
                let w = (IslandLayout.wingsExtra - IslandLayout.peekExtraWidth) * r + 24 * over
                animator.setExtra(IslandMetrics(sw: w, sh: 0, bw: w, bh: 0, tr: 0, br: 0, ic: 0))
            } else {
                let grow = (IslandLayout.chinWidth - Double(g.width) - IslandLayout.peekExtraWidth) * r
                animator.setExtra(IslandMetrics(sw: 0, sh: 0, bw: grow + 24 * over, bh: IslandLayout.chinHeight * r, tr: 0, br: 4 * r, ic: 0))
            }
        default:
            animator.setExtra(.zero)
        }
    }

    /// Up or down over Shazam while it listens: the drag follows the fingers instead of the usual one-shot swipe.
    func shazamDragBegan() -> Bool {
        guard case .shazam(let s)? = content, s.listening, !expanded, presentation == .shazam else { return false }
        dragSpring?.stop(); dragSpring = nil
        shazamDrag = ShazamDrag()
        return true
    }

    /// Up pushes it back into the notch, down stretches it off the bottom, both against a band. Trackpad: a light tick
    /// as it catches, a firm click at the commit point, a light tick going back over it.
    func shazamDragChanged(_ dy: Double) {
        guard var d = shazamDrag, !d.releasing else { return }
        if dy < 0 { d.dir = -1 } else if dy > 0 { d.dir = 1 }
        let wasArmed = d.armed
        d.progress = 1 - 1 / (1 + abs(dy) / Self.shazamDragDistance)
        if !d.caught, d.progress > 0.1 {
            d.caught = true
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        if d.armed != wasArmed {
            NSHapticFeedbackManager.defaultPerformer.perform(d.armed ? .levelChange : .alignment, performanceTime: .now)
        }
        shazamDrag = d
        updateDragShape()
    }

    /// Past the point (and not flung back): it stops, the island folding away the way it was going. Short of it: it
    /// springs back and keeps listening.
    func shazamDragEnded(velocity: Double) {
        guard var d = shazamDrag, !d.releasing else { return }
        guard d.dir != 0 else { clearShazamDrag(); return }
        let pv = (d.dir == 1 ? velocity : -velocity) * (1 - d.progress) * (1 - d.progress) / Self.shazamDragDistance
        if d.armed && pv > -2 {
            shazamDrag = nil
            animator.setExtra(.zero)
            endShazam()
            return
        }
        d.releasing = true
        shazamDrag = d
        dragSpring?.stop()
        dragSpring = ValueSpring(from: d.progress, to: 0, velocity: pv, response: 0.36, damping: 0.62,
                                 update: { [weak self] x in self?.shazamDrag?.progress = max(x, 0); self?.updateDragShape() },
                                 done: { [weak self] in self?.clearShazamDrag() })
    }

    private func cancelShazamPull() {
        pullSpring?.stop(); pullSpring = nil
        guard shazamPull != nil else { return }
        shazamPull = nil
        updatePullShape()
    }

    private func clearShazamDrag() {
        dragSpring?.stop(); dragSpring = nil
        guard shazamDrag != nil else { return }
        shazamDrag = nil
        animator.setExtra(.zero)
    }

    /// Up, the island shrinks back toward the notch; down, its body stretches longer and narrower, like taffy.
    private func updateDragShape() {
        guard let d = shazamDrag, presentation == .shazam else { animator.setExtra(.zero); return }
        let r = d.reach, over = max(d.progress - 0.5, 0)
        if d.dir == -1 {
            let narrow = 46 * r + 20 * over
            let bodyLoss = (wingsFit ? 22 : 26) * r + 6 * over
            animator.setExtra(IslandMetrics(sw: wingsFit ? -narrow : 0, sh: 0, bw: -narrow, bh: -bodyLoss, tr: 0, br: -6 * r, ic: 0))
        } else {
            let narrow = 26 * r + 14 * over
            animator.setExtra(IslandMetrics(sw: wingsFit ? -narrow * 0.4 : 0, sh: 0, bw: -narrow, bh: 20 * r + 34 * over, tr: 0, br: 4 * r, ic: 0))
        }
    }

    /// The button in the controls, or the pull: the island listens, then shows the song. Pulled in, the mark stays on
    /// the side it came from.
    func startShazam(fromRight: Bool = false, pulled: Bool = false) {
        guard !lockScreen, !paused else { return }
        if expanded { collapse() }
        recomputeLayout()
        shazamTask?.cancel()
        shazam = ShazamState(fromRight: fromRight, pulled: pulled)
        refresh()
        shazamListener.listen { [weak self] outcome in self?.shazamFinished(outcome) }
    }

    private func shazamFinished(_ outcome: ShazamListener.Outcome) {
        guard shazam != nil else { return }
        clearShazamDrag() // it answered mid-drag: nothing left to stop
        let phase: ShazamState.Phase = switch outcome {
        case .match(let song): .match(song)
        case .noMatch: .noMatch
        case .micDenied: .micDenied
        case .failed(let message): .failed(message)
        }
        if case .match = phase { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        shazam?.phase = phase
        recomputeLayout()
        refresh()
        // Under the pointer it waits until the pointer leaves.
        if !pointerInside { armShazam(shazam?.hold ?? 3) }
    }

    private func armShazam(_ seconds: Double) {
        shazamTask?.cancel()
        shazamTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.endShazam()
        }
    }

    /// Stops listening (a swipe up, a click while listening) or puts the result away.
    func endShazam() {
        shazamListener.cancel()
        shazamTask?.cancel()
        clearShazamDrag()
        guard shazam != nil else { return }
        shazam = nil
        refresh()
    }

    /// While listening a click stops it; on a song it opens it in Apple Music (or Shazam's page); on no match it
    /// listens again; with the microphone off it opens that pane of System Settings.
    private func shazamClicked() {
        guard let s = shazam else { return }
        switch s.phase {
        case .listening: endShazam()
        case .match(let song):
            endShazam()
            if let url = song.url { NSWorkspace.shared.open(url) }
        case .noMatch, .failed: startShazam(fromRight: s.fromRight)
        case .micDenied:
            endShazam()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// A click outside: closes the panel.
    func dismiss() { collapse() }

    /// A click outside the panel. In search, clicks in the emoji picker are part of typing, so they leave it open.
    func clickedOutside(onto bundleID: String?) {
        if expandedPage == .search, bundleID == "com.apple.CharacterPaletteIM" { return }
        dismiss()
    }

    // MARK: Notifications

    /// Whether a banner can come into the notch now. Otherwise the system shows it as usual.
    func canTakeNotification(_ n: NotificationItem) -> Bool {
        guard geometry != nil, !paused, base == nil, !lockScreen, unlockStart == nil else { return false }
        if !expanded || expandedPage == .notifications { return true }
        // In a conversation: one for that conversation is already on screen (taken, then dropped); others stay macOS's.
        if expandedPage == .messages, n.isMessages, let m = messages { return m.isOpen(m.chatID(for: n)) }
        return false
    }

    func showNotification(_ n: NotificationItem) {
        if expanded && expandedPage == .messages { notificationExpired?(n); return } // it's in the open conversation
        notifications.insert(n, at: 0)
        if notifications.count > 30 { notificationExpired?(notifications.removeLast()) }
        if pointerInside || expanded { notificationTask?.cancel() } else { armNotification(Self.notificationSeconds) }
        refresh()
    }

    private func armNotification(_ seconds: Double) {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.pointerInside, !self.expanded else { return }
            self.endAllNotifications(.expired)
        }
    }

    enum NotificationEnd: Equatable { case shown, closed, expired, action(String) }

    /// One notification is dealt with: opened, closed, or one of its buttons pressed. The list closes once it's empty.
    func removeNotification(_ n: NotificationItem, _ how: NotificationEnd) {
        guard notifications.contains(where: { $0.id == n.id }) else { return }
        notifications.removeAll { $0.id == n.id }
        if openNotificationID == n.id { openNotificationID = nil }
        finish(n, how)
        if notifications.isEmpty {
            notificationTask?.cancel()
            if expanded && expandedPage == .notifications { closeNotificationList() }
        }
        refresh()
    }

    /// The pill: the list on the panel, remembering the page to go back to.
    func openNotificationList() {
        guard expanded, !notifications.isEmpty, expandedPage != .notifications else { return }
        notificationReturnPage = expandedPage
        controlDetail = nil
        openNotificationID = nil
        expandedPage = .notifications
        refresh()
    }

    /// The list's back chevron, or the list emptying: back to the page it came from.
    func closeNotificationList() {
        guard expanded, expandedPage == .notifications else { return }
        expandedPage = notificationReturnPage ?? (mediaPlaying ? .media : .displaySound)
        notificationReturnPage = nil
        openNotificationID = nil
        refresh()
    }

    /// A row of the list clicked: it opens in place (another one closes), or closes again.
    func toggleNotificationRow(_ n: NotificationItem) {
        guard expanded, expandedPage == .notifications else { return }
        openNotificationID = openNotificationID == n.id ? nil : n.id
        refresh()
    }

    /// The open row's Open: the notification in its app (the banner's own Show), and the panel closes so the app shows.
    /// A Messages one opens as its conversation in the panel instead, when it can.
    func openNotificationInApp(_ n: NotificationItem) {
        openConversation(n) { [weak self] in
            self?.removeNotification(n, .shown)
            self?.collapse()
        }
    }

    /// All of them: swiped up, "Clear all", the time running out, or the list closing.
    func endAllNotifications(_ how: NotificationEnd, refreshing: Bool = true) {
        let all = notifications
        guard !all.isEmpty else { return }
        notificationTask?.cancel()
        notifications = []
        all.forEach { finish($0, how) }
        if expanded && expandedPage == .notifications && refreshing { closeNotificationList() }
        if refreshing { refresh() }
    }

    private func finish(_ n: NotificationItem, _ how: NotificationEnd) {
        switch how {
        case .shown: notificationShow?(n)
        case .closed: notificationClose?(n)
        case .expired: notificationExpired?(n)
        case .action(let name): notificationAction?(n, name)
        }
    }

    // MARK: Messages

    /// The card shows buttons: the banner's own, or View for Messages (the conversation, in the notch).
    func notificationHasButtons(_ n: NotificationItem) -> Bool { !n.actions.isEmpty || canReply(n) }
    func canReply(_ n: NotificationItem) -> Bool { n.isMessages && messages?.available == true }

    /// A Messages notification opens as its conversation in the panel (DESIGN.md "Messages"). When it can't be (not
    /// Messages, turned off, no Full Disk Access, not found), `otherwise` runs: it opens in Messages as usual.
    func openConversation(_ n: NotificationItem, otherwise: (() -> Void)? = nil) {
        guard n.isMessages, let m = messages, m.available else { otherwise?(); return }
        // It waits while the conversation is read, so it's still there for `otherwise`.
        notificationTask?.cancel()
        openChat(finding: { await m.findChat(for: n) }, opened: { [weak self] in
            self?.removeNotification(n, .expired) // it stays in Notification Center, like the others
        }, otherwise: otherwise)
    }

    /// The messages pill: the inbox, unread chats first (DESIGN.md "Messages inbox").
    func openInbox() {
        guard let m = messages, m.available else { return }
        if expandedPage == .messages { m.close() }
        m.refreshInbox()
        controlDetail = nil
        expandedPage = .inbox
        if !expanded { setExpanded(true) } else { refresh() }
    }

    /// From the inbox back to the controls.
    func closeInbox() {
        guard expanded else { return }
        expandedPage = mediaPlaying ? .media : .displaySound
        refresh()
    }

    /// Opens a conversation on the panel by its chat.
    func openChat(_ chat: Int64) { openChat(finding: { chat }) }

    /// Finds the chat and reads it in the background, so the island keeps animating meanwhile, then shows it. The
    /// latest request wins; `otherwise` runs when there's nothing to show.
    private func openChat(finding find: @escaping @MainActor () async -> Int64?, opened: (() -> Void)? = nil,
                          otherwise: (() -> Void)? = nil) {
        guard let m = messages else { otherwise?(); return }
        chatOpening?.cancel()
        chatOpening = Task { [weak self] in
            let chat = await find()
            let ok = if let chat { await m.openChat(chat) } else { false }
            guard !Task.isCancelled, let self else { return }
            self.chatOpening = nil
            guard ok else { otherwise?(); return }
            if self.expandedPage == .search { self.search.end() } // from search's Message: the conversation takes its place
            self.expandedPage = .messages // first, so taking a notification off the list doesn't close the panel
            self.controlDetail = nil
            opened?()
            if !self.expanded { self.setExpanded(true) } else { self.refresh() }
        }
    }
    @ObservationIgnored private var chatOpening: Task<Void, Never>?

    func setBase(_ p: Presentation?) {
        base = p
        refresh()
    }

    /// Something that feeds `presentation` changed without a store property changing (the scan's phases).
    func presentationChanged() { refresh() }

    func setLockScreen(_ value: Bool) {
        guard value != lockScreen else { return }
        lockScreen = value
        // Locking stops Shazam: the microphone isn't left on behind the lock screen, and no stale song waits for the
        // unlock. A pull in progress lets go.
        if value { endShazam(); cancelShazamPull() }
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
        // Paused from the menu: Shazam stops rather than listening unseen, or leaving a song that would never time out
        // (the pointer is taken out without the hover's timer).
        if value { endShazam(); cancelShazamPull() }
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

    /// The charger event that's showing, with news that came after it (the time to full); its timer carries on.
    func updateCharge(_ event: ChargeEvent) {
        guard charge?.kind == event.kind else { return }
        charge = event
    }

    /// A join's progress. It shows whenever the panel isn't open, unlike connection notices: the user is waiting on
    /// it. The result stays a moment (an error longer), then hands back.
    func showProgress(_ p: ConnectionProgress, action: (() -> Void)? = nil) {
        recomputeLayout()
        progress = p
        progressAction = action
        progressTask?.cancel()
        let hold: Double? = switch p.state { case .working: nil; case .done: p.hold ?? 2.5; case .failed: p.hold ?? 4 }
        if let hold {
            progressTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(hold))
                guard !Task.isCancelled else { return }
                self?.progress = nil
                self?.progressAction = nil
                self?.refresh()
            }
        }
        refresh()
    }

    /// Takes the progress away at once (the update, just before Islet quits), so the island draws back in.
    func clearProgress() {
        progressTask?.cancel(); progress = nil; progressAction = nil
        refresh()
    }

    /// Whether an event would show now (it is dropped otherwise).
    var canShowEvent: Bool {
        geometry != nil && !paused && !lockScreen && !expanded && Date().timeIntervalSince(lastInUse) > Self.quietAfterUse
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

    /// The front app changed: media playing in it leaves the notch, and comes back when you switch away.
    func setFrontApp(_ bundleID: String?) {
        guard bundleID != frontBundleID else { return }
        let before = mediaVisible
        frontBundleID = bundleID
        if before != mediaVisible { recomputeLayout(); refresh() }
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
