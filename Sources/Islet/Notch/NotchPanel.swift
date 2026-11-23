import AppKit
import SwiftUI

/// Borderless, non-activating panel that sits over the menu bar at the top centre of the notched display.
final class NotchPanel: NSPanel {
    var allowsKey = false
    var onCancel: (() -> Void)?
    /// Every two-finger scroll, before it goes to whatever is under the pointer (a list scrolls it too).
    var onScroll: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel { onScroll?(event) }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Hosts the SwiftUI island and turns two-finger scrolls into swipes: up and down fire once past a threshold;
/// left and right are followed continuously (skip and previous) and end exactly when the fingers lift.
final class IslandHostingView: NSHostingView<IslandView> {
    enum Swipe { case up, down }
    var onSwipe: ((Swipe) -> Void)?
    /// Sideways: began (return false to ignore this swipe), finger travel so far (+ right), lifted at a speed (pt/s).
    var onSideBegan: (() -> Bool)?
    var onSideChanged: ((CGFloat) -> Void)?
    var onSideEnded: ((CGFloat) -> Void)?
    /// A list in the panel under this point (top-left window points), and whether it's at its top / bottom.
    var listAt: ((CGPoint) -> (atTop: Bool, atBottom: Bool)?)?
    /// The list under the fingers when this gesture began; nil when it began elsewhere.
    private var list: (atTop: Bool, atBottom: Bool)?

    private enum Axis { case undecided, vertical, horizontal, ignored }
    private var axis = Axis.undecided
    private var accX: CGFloat = 0
    private var accY: CGFloat = 0
    private var fired = false
    private var samples: [(t: TimeInterval, x: CGFloat)] = []
    private let threshold: CGFloat = 40

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The panel hands every scroll here (`NotchPanel.onScroll`) as well as to whatever is under the pointer, so a list
    /// in the panel can scroll while this decides whether the gesture is also a swipe.
    override func scrollWheel(with event: NSEvent) {}

    func track(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        // The trackpad keeps coasting after the fingers lift; that never counts.
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) {
            reset()
            let p = convert(event.locationInWindow, from: nil)
            list = listAt?(CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y))
        }
        // Normalise to finger movement, regardless of the natural-scrolling setting: x + is right, y - is up.
        let inverted = event.isDirectionInvertedFromDevice
        let fx = inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        let fy = inverted ? event.scrollingDeltaY : -event.scrollingDeltaY
        if event.phase.contains(.began) || event.phase.contains(.changed) {
            accX += fx; accY += fy
            if axis == .undecided && hypot(accX, accY) >= 5 {
                if abs(accX) > abs(accY) {
                    axis = (onSideBegan?() ?? false) ? .horizontal : .ignored
                } else {
                    axis = .vertical
                }
            }
            switch axis {
            case .vertical:
                if !fired && abs(accY) >= threshold {
                    fired = true
                    let swipe: Swipe = accY < 0 ? .up : .down
                    // Over a list, the fingers scroll it. Up still closes when the list can't go that way any more:
                    // with natural scrolling, fingers up move toward the bottom (the newest message).
                    if let list {
                        let stuck = event.isDirectionInvertedFromDevice ? list.atBottom : list.atTop
                        if swipe == .up && stuck { onSwipe?(swipe) }
                    } else {
                        onSwipe?(swipe)
                    }
                }
            case .horizontal:
                samples.append((event.timestamp, accX))
                if samples.count > 12 { samples.removeFirst() }
                onSideChanged?(accX)
            default: break
            }
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if axis == .horizontal { onSideEnded?(velocity(at: event.timestamp)) }
            reset()
        }
    }

    /// Finger speed over the last 80 ms of the swipe. A pause before lifting reads as zero.
    private func velocity(at now: TimeInterval) -> CGFloat {
        let recent = samples.filter { now - $0.t < 0.08 }
        guard let first = recent.first, let last = recent.last, last.t > first.t else { return 0 }
        return (last.x - first.x) / CGFloat(last.t - first.t)
    }

    private func reset() { axis = .undecided; accX = 0; accY = 0; fired = false; samples = []; list = nil }
}

/// Owns the panel and the pointer/click/screen monitors that feed the store.
@MainActor
final class NotchController {
    let store = IslandStore()
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    /// Sees every pointer move, whichever app is in front (see `installMonitors`).
    private var pointerTap: CFMachPort?
    private var lastPointer: NSPoint?
    private var screenObserver: NSObjectProtocol?
    /// Without a notch: where the island hangs, from Islet's menu bar icon (its centre x, the menu bar's bottom
    /// and its screen). nil when the icon isn't on screen.
    var menuBarAnchor: (() -> (x: CGFloat, bottom: CGFloat, screen: CGRect)?)?
    /// The last place the icon was seen, kept for when its window is away (the lock screen has no status items).
    private var lastAnchor: (x: CGFloat, bottom: CGFloat, screen: CGRect)?
    /// The island is under the menu bar icon rather than in a notch.
    var inMenuBar: Bool { store.geometry?.mode == .menuBar }

    /// An update's handoff: the new copy draws its island unseen under the old one's, then shows it in one step.
    func setIslandVisible(_ visible: Bool) { panel?.alphaValue = visible ? 1 : 0 }

    func start() {
        let host = IslandHostingView(rootView: IslandView(store: store))
        host.sizingOptions = []
        host.onSwipe = { [weak self] swipe in
            switch swipe {
            case .up: self?.store.swipeUp()
            case .down: self?.store.swipeDown()
            }
        }
        host.onSideBegan = { [weak self] in self?.store.skipBegan() ?? false }
        host.onSideChanged = { [weak self] dx in self?.store.skipChanged(Double(dx)) }
        host.onSideEnded = { [weak self] v in self?.store.skipEnded(velocity: Double(v)) }

        host.listAt = { [weak self] p in self?.store.scrollRegion(at: p).map { ($0.atTop, $0.atBottom) } }
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.onScroll = { [weak host] in host?.track($0) }
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Far above everything, and allowed on the login/lock screen (see SkyLightSpace).
        panel.level = Self.islandLevel
        panel.canBecomeVisibleWithoutLogin = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.onCancel = { [weak self] in self?.store.dismiss() }
        self.panel = panel

        store.onCharacterPalette = { [weak self] in self?.yieldToCharacterPalette() }
        store.onExpandedChange = { [weak self] expanded in
            guard let panel = self?.panel else { return }
            panel.allowsKey = expanded
            if expanded { panel.makeKey() } else if panel.isKeyWindow { panel.resignKey() }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }

        installMonitors()
        screenChanged()
    }

    /// The island's own level: above nearly everything, so it shows over full-screen apps and the lock screen.
    static let islandLevel = NSWindow.Level(rawValue: Int(Int32.max - 2))
    private var paletteWatch: Task<Void, Never>?

    /// Emoji & Symbols opens in its own process at a level under the island's, so it appeared behind the panel. While
    /// it's on screen the panel steps down to just under it, then goes back up once it closes.
    func yieldToCharacterPalette() {
        paletteWatch?.cancel()
        paletteWatch = Task { [weak self] in
            var seen = false
            for _ in 0..<600 { // up to a minute between looks at it; it's usually closed well before
                try? await Task.sleep(for: .milliseconds(seen ? 300 : 80))
                guard let self, !Task.isCancelled, let panel = self.panel else { return }
                if let layer = Self.characterPaletteLayer() {
                    seen = true
                    let under = NSWindow.Level(rawValue: layer - 1)
                    if panel.level != under { panel.level = under }
                } else if seen {
                    break
                }
            }
            self?.panel?.level = Self.islandLevel
        }
    }

    /// The window layer of the open Emoji & Symbols picker, if it's on screen.
    private static func characterPaletteLayer() -> Int? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Emoji & Symbols" || owner.contains("CharacterPalette"),
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
                  r.height > 100, let layer = w[kCGWindowLayer as String] as? Int else { continue }
            // Only step down to a level that still floats over apps' windows.
            guard layer > NSWindow.Level.statusBar.rawValue else { return nil }
            return min(layer, Int(Int32.max - 2))
        }
        return nil
    }

    func setPaused(_ paused: Bool) {
        store.setPaused(paused)
        updatePanelVisibility()
    }

    // MARK: Screen

    func screenChanged() {
        let g = NotchGeometry.current() ?? menuBarGeometry()
        if g != store.geometry { store.setGeometry(g) }
        if let g { panel?.setFrame(g.panelFrame, display: true) }
        updatePanelVisibility()
    }

    /// No notch: the island floating under the camera, under the menu bar icon, or none, as the owner chose.
    private func menuBarGeometry() -> NotchGeometry? {
        switch NotchlessStyle.current {
        case .off: return nil
        case .bezel: return NotchGeometry.bezel()
        case .menuBar: break
        }
        if let a = menuBarAnchor?(), a.screen.contains(CGPoint(x: a.x, y: a.bottom)) { lastAnchor = a }
        guard let a = lastAnchor ?? NSScreen.main.map({ s in
            (x: s.frame.maxX - 200, bottom: s.visibleFrame.maxY, screen: s.frame)
        }) else { return nil }
        return NotchGeometry.underMenuBar(anchorX: a.x, menuBarBottom: a.bottom, screen: a.screen)
    }

    /// The menu bar icon was clicked (menu bar mode): open or close the island under it.
    func toggleFromMenuBar() {
        if store.expanded { store.collapse(); return }
        screenChanged() // the icon may have moved since
        store.expand()
    }

    private func updatePanelVisibility() {
        guard let panel else { return }
        if store.geometry != nil && !store.paused {
            panel.orderFrontRegardless()
            SkyLightSpace.shared.attach(panel) // so it also shows over the lock screen
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: Pointer

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Global monitors see events going to other apps (the panel ignores the mouse outside the island). macOS only
        // sends pointer moves to them while the app in front asks for moves, which the desktop (Finder with no window)
        // doesn't: so a listen-only event tap watches them too. It never holds or changes an event.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerChanged() }
        }) { monitors.append(m) }
        installPointerTap()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clickMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedElsewhere() }
        }) { monitors.append(m) }
        // Keys while the panel has the keyboard: search's arrows, Return and Esc, and a letter typed in the open panel
        // starting a search (DESIGN.md "Search").
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.store.handleKey(KeyPress(event)) ?? false }
            return handled ? nil : event
        }) { monitors.append(m) }
        // Local monitor covers moves while the pointer is over the panel itself.
        if let m = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerChanged() }
            return event
        }) { monitors.append(m) }
    }

    private func installPointerTap() {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue) | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            if let info, type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                let me = Unmanaged<NotchController>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated { if let t = me.pointerTap { CGEvent.tapEnable(tap: t, enable: true) } }
            } else if let info {
                let me = Unmanaged<NotchController>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated { me.pointerChanged() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        pointerTap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func pointerChanged() {
        // The tap and the monitors both report most moves: one look per position is enough.
        let at = NSEvent.mouseLocation
        if at == lastPointer { return }
        lastPointer = at
        var inside = store.isOverIsland(globalPoint: NSEvent.mouseLocation)
        // Mission Control's Spaces bar runs along the top: the island doesn't answer the pointer there, so the peek
        // (and, without a notch, the chevron) stays away and clicks reach the bar (DESIGN.md "Behaviour").
        if inside, !store.expanded, DockOverview.isOpen() { inside = false }
        panel?.ignoresMouseEvents = !inside
        store.pointerMoved(inside: inside)
    }

    private func clickedElsewhere() {
        // Only global clicks arrive here, so by definition they landed outside our panel.
        let point = NSEvent.mouseLocation
        if !store.isOverIsland(globalPoint: point) { store.clickedOutside(onto: Self.owner(at: point)) }
    }

    /// The app whose window is under a point on screen (AppKit coordinates), front to back.
    private static func owner(at p: NSPoint) -> String? {
        guard let top = NSScreen.screens.first?.frame.maxY,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let q = CGPoint(x: p.x, y: top - p.y)
        for w in list {
            guard let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b), r.contains(q),
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != getpid() else { continue }
            return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        return nil
    }
}

/// A key press, as the store needs it.
struct KeyPress {
    let code: UInt16
    let characters: String?
    let charactersIgnoringModifiers: String?
    let command, control: Bool
    /// The field being typed in has text selected (⌘C copies that, not the selected result).
    let fieldHasSelection: Bool

    static let returnKey: UInt16 = 36, tab: UInt16 = 48, space: UInt16 = 49, delete: UInt16 = 51, escape: UInt16 = 53, enter: UInt16 = 76
    static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126

    @MainActor init(_ e: NSEvent) {
        code = e.keyCode
        characters = e.characters
        charactersIgnoringModifiers = e.charactersIgnoringModifiers
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        command = flags.contains(.command)
        control = flags.contains(.control)
        fieldHasSelection = ((NSApp.keyWindow?.firstResponder as? NSTextView)?.selectedRange().length ?? 0) > 0
    }

    /// Text to type: printable characters with no Command or Control (Option and Shift letters count).
    var plainText: Bool {
        guard !command, !control, let c = characters, !c.isEmpty else { return false }
        return c.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }
    }
}

/// Whether Mission Control (or another of the Dock's full-screen views, like the app grid) is open. macOS posts no
/// event Islet can hear for it (the Dock's Expose notifications stay silent on macOS 26), but while it's open the Dock
/// owns a window covering the whole screen (layer 20, the menu bar stays listed: checked on macOS 27, 2026-11-23).
/// Only asked while the pointer is over the island, and at most 4 times a second.
@MainActor
enum DockOverview {
    private static var checkedAt = Date.distantPast
    private static var open = false

    static func isOpen() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(checkedAt) > 0.25 else { return open }
        checkedAt = now
        open = read()
        return open
    }

    private static func read() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let screens = NSScreen.screens.map(\.frame)
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == dock.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int ?? 0) >= Int(CGWindowLevelForKey(.dockWindow)),
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], let height = b["Height"] else { return false }
            return screens.contains { width >= $0.width - 1 && height >= $0.height - 1 }
        }
    }
}
