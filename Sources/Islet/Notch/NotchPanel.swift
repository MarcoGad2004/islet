import AppKit
import SwiftUI

/// Borderless, non-activating panel that sits over the menu bar at the top centre of the notched display.
final class NotchPanel: NSPanel {
    var allowsKey = false
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Hosts the SwiftUI island and turns two-finger scrolls into swipes.
final class IslandHostingView: NSHostingView<IslandView> {
    enum Swipe { case up, down }
    var onSwipe: ((Swipe) -> Void)?

    private var accumulated: CGFloat = 0
    private var fired = false
    private let threshold: CGFloat = 40

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        if event.phase.contains(.began) { accumulated = 0; fired = false }
        // Normalise to finger movement: negative = fingers moved up, regardless of the natural-scrolling setting.
        let fingerDelta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        if event.phase.contains(.changed) || event.phase.contains(.began) {
            accumulated += fingerDelta
            if !fired && abs(accumulated) >= threshold {
                fired = true
                onSwipe?(accumulated < 0 ? .up : .down)
            }
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { accumulated = 0; fired = false }
    }
}

/// Owns the panel and the pointer/click/screen monitors that feed the store.
@MainActor
final class NotchController {
    let store = IslandStore()
    private var panel: NotchPanel?
    private var monitors: [Any] = []
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

        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Far above everything, and allowed on the login/lock screen (see SkyLightSpace).
        panel.level = NSWindow.Level(rawValue: Int(Int32.max - 2))
        panel.canBecomeVisibleWithoutLogin = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.onCancel = { [weak self] in self?.store.dismiss() }
        self.panel = panel

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

        // Global monitors see events going to other apps (the panel ignores the mouse outside the island).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerChanged() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clickMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedElsewhere() }
        }) { monitors.append(m) }
        // Local monitor covers moves while the pointer is over the panel itself.
        if let m = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerChanged() }
            return event
        }) { monitors.append(m) }
    }

    private func pointerChanged() {
        let inside = store.isOverIsland(globalPoint: NSEvent.mouseLocation)
        panel?.ignoresMouseEvents = !inside
        store.pointerMoved(inside: inside)
    }

    private func clickedElsewhere() {
        // Only global clicks arrive here, so by definition they landed outside our panel.
        if !store.isOverIsland(globalPoint: NSEvent.mouseLocation) { store.dismiss() }
    }
}
