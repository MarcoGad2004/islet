import AppKit
import SwiftUI

/// The battery icon's stats, dropped down under it like a menu bar extra's window. A click anywhere else, Esc, or
/// another click on the icon closes it.
@MainActor
final class BatteryStatsPanel {
    private let power: PowerMonitor
    private var panel: NSPanel?
    private var host: FittingHostingView<AnyView>?
    private var monitors: [Any] = []
    /// The icon's window: a click on the icon toggles, so the outside-click watcher leaves it alone.
    private weak var anchor: NSWindow?
    var openControls: (() -> Void)?

    var isOpen: Bool { panel?.isVisible == true }

    init(power: PowerMonitor) { self.power = power }

    func toggle(under button: NSStatusBarButton) {
        if isOpen { close() } else { show(under: button) }
    }

    func show(under button: NSStatusBarButton) {
        guard let window = button.window else { return }
        anchor = window
        let panel = self.panel ?? makePanel()
        power.refresh()
        power.watchDetails(true)
        power.history.backfillIfNeeded()
        fit(below: window)
        panel.orderFrontRegardless()
        panel.makeKey()
        button.highlight(true)
        watchOutside(button)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        power.watchDetails(false)
        (anchor?.contentView?.subviews.first { $0 is NSStatusBarButton } as? NSStatusBarButton)?.highlight(false)
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in self?.close() }

        let radius: CGFloat = 14
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.maskImage = Self.roundedMask(radius)

        let content = BatteryStatsView(power: power, openControls: { [weak self] in
            self?.close()
            self?.openControls?()
        })
        .background(Color.black.opacity(0.35))
        let host = FittingHostingView(rootView: AnyView(content))
        host.onSizeChange = { [weak self] in
            guard let self, let w = self.anchor, self.isOpen else { return }
            self.fit(below: w)
        }
        host.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass
        self.host = host
        self.panel = panel
        return panel
    }

    /// Under the icon with a small gap, its left edge at the icon's, kept on screen.
    private func fit(below window: NSWindow) {
        guard let panel, let host, let screen = window.screen ?? NSScreen.main else { return }
        let size = host.fittingSize
        let visible = screen.visibleFrame
        var x = window.frame.minX
        x = min(x, visible.maxX - size.width - 8)
        x = max(x, visible.minX + 8)
        let top = window.frame.minY - 5
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func watchOutside(_ button: NSStatusBarButton) {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(m) }
        // Clicks in Islet's own windows (the island, Settings), but not the icon, which toggles it itself.
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel, event.window !== self.anchor else { return }
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
