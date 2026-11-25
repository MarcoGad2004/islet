import AppKit
import SwiftUI

/// The battery icon's stats (DESIGN.md "Menu bar battery").
@MainActor
final class BatteryStatsPanel {
    private let power: PowerMonitor
    var openControls: (() -> Void)?
    private lazy var panel: MenuBarPanel = {
        let panel = MenuBarPanel { [weak self] close in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(BatteryStatsView(power: self.power, openControls: { [weak self] in
                close()
                self?.openControls?()
            }))
        }
        panel.willShow = { [weak self] in
            guard let power = self?.power else { return }
            power.refresh()
            power.watchDetails(true, owner: "stats")
            PowerModeController.shared.refresh()
            power.history.backfillIfNeeded()
        }
        panel.didClose = { [weak self] in self?.power.watchDetails(false, owner: "stats") }
        return panel
    }()

    init(power: PowerMonitor) { self.power = power }

    var isOpen: Bool { panel.isOpen }
    func toggle(under button: NSStatusBarButton) { panel.toggle(under: button) }
    func show(under button: NSStatusBarButton) { panel.show(under: button) }
    func close() { panel.close() }
}

/// A window dropped down under a menu bar icon like a menu bar extra's, with the battery stats' look (glass or the dark
/// panel). A click anywhere else, Esc, or another click on the icon closes it. Used by the battery stats and Mac Stats.
@MainActor
final class MenuBarPanel {
    private let makeContent: (@escaping () -> Void) -> AnyView
    /// Before it shows: start the readings it needs.
    var willShow: (() -> Void)?
    /// Once it's gone: stop them.
    var didClose: (() -> Void)?
    private var panel: NSPanel?
    private var host: FittingHostingView<AnyView>?
    private var monitors: [Any] = []
    private var systemObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var shownAt = Date.distantPast
    /// The icon's window: a click on the icon toggles, so the outside-click watcher leaves it alone.
    private weak var anchor: NSWindow?
    private var closedByOutsideClick: Date?

    /// Fading out: still on screen, but already closed as far as anyone asking is concerned.
    private var closing = false
    /// Bumped on each show and close, so a fade-out that ends after the panel was shown again leaves it alone.
    private var generation = 0

    var isOpen: Bool { panel?.isVisible == true && !closing }
    private var builtGlass: Bool?

    /// Liquid Glass (macOS 26 and later) when the island uses the glass look (DESIGN.md "Glass").
    private static var wantsGlass: Bool {
        guard #available(macOS 26, *) else { return false }
        return UserDefaults.standard.object(forKey: GlassLook.key) as? Bool ?? true
    }

    /// The content gets a way to close the panel.
    init(content: @escaping (_ close: @escaping () -> Void) -> AnyView) { makeContent = content }

    func toggle(under button: NSStatusBarButton) {
        if isOpen { close(); return }
        // The press on the icon can already have closed the panel as an outside click; this click's action must not
        // open it again.
        if let t = closedByOutsideClick, Date().timeIntervalSince(t) < 0.4 { closedByOutsideClick = nil; return }
        show(under: button)
    }

    func show(under button: NSStatusBarButton) {
        guard let window = button.window else { return }
        anchor = window
        // The look follows the glass setting; a change since the panel was made builds it again.
        let glass = Self.wantsGlass
        if self.panel != nil, builtGlass != glass { self.panel?.orderOut(nil); self.panel = nil; self.host = nil }
        let panel = self.panel ?? makePanel(glass: glass)
        willShow?()
        // The content only lives while the panel shows: hidden, its animations (the power flow's) and readings would
        // keep SwiftUI redrawing it every frame for nothing.
        host?.rootView = root(glass: glass)
        generation += 1
        closing = false
        panel.ignoresMouseEvents = false
        // Shown again while it was still fading out: carry on from where the fade had got to.
        let from = panel.isVisible ? panel.alphaValue : 0
        fit(below: window)
        appear(panel, from: from)
        panel.orderFrontRegardless()
        panel.makeKey()
        button.highlight(true)
        watchOutside(button)
        watchSystem()
    }

    /// Another app coming forward, a change of Space, the display going to sleep or the screen locking: a menu closes
    /// then, and so does this. Left open, its readings (the app lists, the one-second battery reads, the power
    /// flow's animation) would run on for nothing, out of sight.
    private func watchSystem() {
        unwatchSystem()
        shownAt = Date()
        let close: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                // Not for one still being delivered as the panel opens (the click that opened it can activate us).
                guard let self, Date().timeIntervalSince(self.shownAt) > 0.4 else { return }
                self.close()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.screensDidSleepNotification] {
            systemObservers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main, using: close)))
        }
        let distributed = DistributedNotificationCenter.default()
        systemObservers.append((distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                                     object: nil, queue: .main, using: close)))
    }

    private func unwatchSystem() {
        for (center, token) in systemObservers { center.removeObserver(token) }
        systemObservers = []
    }

    /// Fades in while dropping the last few points into place, like Control Center's modules (only the fade with
    /// Reduce Motion).
    private func appear(_ panel: NSPanel, from alpha: CGFloat) {
        let target = panel.frame
        panel.alphaValue = alpha
        let drops = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && alpha == 0
        if drops { panel.setFrame(target.offsetBy(dx: 0, dy: Self.drop), display: false) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = Self.settle
            panel.animator().alphaValue = 1
            if drops { panel.animator().setFrame(target, display: true) }
        }
    }

    func close() {
        guard let panel, panel.isVisible, !closing else { return }
        closing = true
        generation += 1
        let fading = generation
        // Gone at once as far as clicks go; the look fades out after.
        panel.ignoresMouseEvents = true
        didClose?()
        (anchor?.contentView?.subviews.first { $0 is NSStatusBarButton } as? NSStatusBarButton)?.highlight(false)
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        unwatchSystem()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Shown again meanwhile: leave it.
                guard let self, self.generation == fading, let panel = self.panel else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.closing = false
                self.host?.rootView = AnyView(EmptyView())
            }
        })
    }

    /// How far the panel drops as it appears, in points.
    private static let drop: CGFloat = 6
    /// Fast out, long settle: the panel's appearing and its size changes, matched by the pages' fade-in
    /// (`MacStatsMotion.settle`).
    static let settle = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

    private func makePanel(glass: Bool) -> NSPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in self?.close() }

        let host = FittingHostingView(rootView: AnyView(EmptyView()))
        host.onSizeChange = { [weak self] in
            guard let self, let w = self.anchor, self.isOpen else { return }
            self.fit(below: w, animated: true)
        }
        // The window decides the size while it eases to a new one; the content keeps to the top meanwhile.
        host.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        host.setContentHuggingPriority(.defaultLow, for: .vertical)

        if glass, #available(macOS 26, *) {
            // Liquid Glass, as in Control Center: the desktop shows through blurred and refracted at the edges.
            // No tint or forced appearance of our own: the system's glass then follows System Settings (Liquid Glass
            // clear or tinted, Reduce Transparency) like Control Center does.
            let view = NSGlassEffectView()
            view.cornerRadius = 24
            view.contentView = host
            // The system's glass as it comes (clear, light or dark with the Mac's appearance), so the Liquid Glass and
            // Reduce Transparency settings apply; the text takes the adaptive label colours to stay readable on it.
            // Clipped to the rounded shape, so nothing square can show round the glass.
            let clip = NSView()
            clip.wantsLayer = true
            clip.layer?.cornerRadius = 24
            clip.layer?.cornerCurve = .continuous
            clip.layer?.masksToBounds = true
            view.translatesAutoresizingMaskIntoConstraints = false
            clip.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
                view.topAnchor.constraint(equalTo: clip.topAnchor),
                view.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            ])
            panel.contentView = clip
            // The window's own shadow is drawn for its square frame, which showed as a dark box around the glass.
            panel.hasShadow = false
        } else {
            let radius: CGFloat = 14
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.appearance = NSAppearance(named: .darkAqua)
            blur.maskImage = Self.roundedMask(radius)
            host.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                host.topAnchor.constraint(equalTo: blur.topAnchor),
                host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            ])
            panel.contentView = blur
        }
        builtGlass = glass
        self.host = host
        self.panel = panel
        return panel
    }

    private func root(glass: Bool) -> AnyView {
        let content = makeContent { [weak self] in self?.close() }
        // Glass: the tiles and pills turn to glass too, and the text sits on the glass with a dark tint behind it.
        .environment(\.isletGlass, glass)
        .environment(\.isletAdaptiveInk, glass)
        .background(glass ? Color.clear : Color.black.opacity(0.35))
        // Kept to the top while the panel eases to a new size, so nothing moves but the bottom edge.
        .frame(maxHeight: .infinity, alignment: .top)
        return AnyView(content)
    }

    /// Under the icon with a small gap, its left edge at the icon's, kept on screen.
    /// `animated`: the panel eases to its new size (a page with more or less in it), its top edge staying put.
    private func fit(below window: NSWindow, animated: Bool = false) {
        guard let panel, let host, let screen = window.screen ?? NSScreen.main else { return }
        let size = host.fittingSize
        let visible = screen.visibleFrame
        var x = window.frame.minX
        x = min(x, visible.maxX - size.width - 8)
        x = max(x, visible.minX + 8)
        let top = window.frame.minY - 5
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        guard frame != panel.frame else { return }
        if animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = Self.settle
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// The pointer is on the icon. The status item can be delivered the press from a window other than `anchor`, so
    /// the position is checked too; otherwise the press closes the panel and the click's action opens it again.
    private var overIcon: Bool {
        guard let frame = anchor?.frame else { return false }
        return frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func watchOutside(_ button: NSStatusBarButton) {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.overIcon else { return }
                self.closedByOutsideClick = Date()
                self.close()
            }
        }) { monitors.append(m) }
        // Clicks in Islet's own windows (the island, Settings), but not the icon, which toggles it itself.
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel, event.window !== self.anchor, !self.overIcon else { return }
                self.closedByOutsideClick = Date()
                self.close()
            }
            return event
        }) { monitors.append(m) }
    }

    private static func roundedMask(_ radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A borderless panel that can take Esc without making Islet the active app.
private final class KeyPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Tells its owner when SwiftUI's content changes size (a row appears, the chart fills in), so the panel can follow.
private final class FittingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?
    private var last: NSSize = .zero
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        let size = fittingSize
        guard size != last else { return }
        last = size
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}
