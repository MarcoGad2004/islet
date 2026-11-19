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
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
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

    /// Debug: change the window level (nil restores the normal one). Used by the M2 lock-screen spike.
    func setDebugLevel(_ level: NSWindow.Level?) {
        panel?.level = level ?? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    }

    func setPaused(_ paused: Bool) {
        store.setPaused(paused)
        updatePanelVisibility()
    }

    // MARK: Screen

    private func screenChanged() {
        store.setGeometry(NotchGeometry.current())
        if let g = store.geometry { panel?.setFrame(g.panelFrame, display: true) }
        updatePanelVisibility()
    }

    private func updatePanelVisibility() {
        guard let panel else { return }
        if store.geometry != nil && !store.paused {
            panel.orderFrontRegardless()
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
