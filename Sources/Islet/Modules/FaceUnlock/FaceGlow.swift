import AppKit
import Metal
import QuartzCore
import os

/// The face unlock glow: a full-screen layer of light on the built-in display that lights the face for the depth
/// check (`FacePulse.Glow`), whatever the wallpaper. It sits just under the island, in the same lock-screen space
/// (SkyLightSpace), so it shows over the lock screen while the island and its scan stay on top. It never takes
/// clicks.
///
/// It draws through an EDR Metal layer, so on an XDR panel it can go past SDR white towards the panel's peak. macOS
/// raises that headroom over ~1.3 s once EDR content is on screen, even fully transparent, and keeps it ~10 s after
/// (verified 2026-11-23), so `warm()` puts an invisible layer up as the scan starts and the light is ready by the time
/// the face matches.
@MainActor
final class FaceGlow {
    static let shared = FaceGlow()
    private static let log = Logger(subsystem: "com.marcogad.islet", category: "faceunlock")

    /// Just under the island's own level.
    static let level = NSWindow.Level(rawValue: NotchController.islandLevel.rawValue - 1)
    /// Longest it stays warm without being asked again.
    static let warmSeconds = 30.0

    private let device = MTLCreateSystemDefaultDevice()
    private lazy var queue = device?.makeCommandQueue()
    private var panel: NSPanel?
    private var layer: CAMetalLayer?
    private var warmTask: Task<Void, Never>?
    private var playing = false
    private var cancelled = false

    var isAvailable: Bool { device != nil && Self.builtInScreen != nil }

    private static var builtInScreen: NSScreen? {
        NSScreen.screens.first { s in
            (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        }
    }

    /// Puts the invisible layer up so the panel's extra brightness is ready. Ends with `cool()` or after
    /// `warmSeconds`.
    func warm() {
        guard show() else { return }
        if !playing { draw(0, 0) }
        warmTask?.cancel()
        warmTask = Task { [weak self] in
            let end = Date().addingTimeInterval(Self.warmSeconds)
            while Date() < end {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                if !self.playing { self.draw(0, 0) }
            }
            self?.cool()
        }
    }

    /// Takes it down, ending a glow that's playing.
    func cool() {
        warmTask?.cancel(); warmTask = nil
        if playing { cancelled = true; return }
        draw(0, 0)
        panel?.orderOut(nil)
    }

    /// The levels for a share of the panel's peak (`FacePulse.glowShare`), from the display as it is now.
    func plan(share: Double) -> FacePulse.Glow? {
        guard let screen = Self.builtInScreen else { return nil }
        return FacePulse.Glow(share: share, potential: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue),
                              headroom: Double(screen.maximumExtendedDynamicRangeColorComponentValue))
    }

    /// Plays the glow for a share of the panel's peak. If the extra brightness isn't up yet it waits for it (up to
    /// 1.5 s, the layer invisible meanwhile), so the steps aren't clipped. `onStart` gets the schedule as the glow
    /// starts fading in; returns it once it has faded out, or nil when it couldn't be shown.
    func play(share: Double, onStart: (FacePulse.Schedule) -> Void = { _ in }) async -> FacePulse.Schedule? {
        guard !playing, show(), let screen = Self.builtInScreen else { return nil }
        playing = true; cancelled = false
        defer {
            playing = false
            draw(0, 0)
            if cancelled || warmTask == nil { panel?.orderOut(nil) }
        }
        let wanted = FacePulse.Glow(share: share, potential: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue),
                                    headroom: .infinity).high
        let waitUntil = Date().addingTimeInterval(1.5)
        while Double(screen.maximumExtendedDynamicRangeColorComponentValue) < wanted * 0.95, Date() < waitUntil, !cancelled {
            draw(0, 0)
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !cancelled, let glow = plan(share: share) else { return nil }
        Self.log.notice("glow share=\(share) low=\(glow.low) high=\(glow.high) steps=\(glow.steps.map { $0 ? "H" : "L" }.joined(), privacy: .public)")

        let start = Date()
        let schedule = glow.schedule(start: start)
        onStart(schedule)
        while !cancelled {
            let t = Date().timeIntervalSince(start)
            if t >= glow.total { break }
            let (v, a) = glow.at(t)
            draw(v, a)
            try? await Task.sleep(for: .milliseconds(12))
        }
        return cancelled ? nil : schedule
    }

    // MARK: Window

    /// Puts the window on the built-in screen, at its full size. False when there's no such screen or no Metal.
    private func show() -> Bool {
        guard let device, let screen = Self.builtInScreen else { return false }
        if panel == nil {
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = Self.level
            p.canBecomeVisibleWithoutLogin = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.ignoresMouseEvents = true
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let l = CAMetalLayer()
            l.device = device
            l.pixelFormat = .rgba16Float
            l.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
            l.wantsExtendedDynamicRangeContent = true
            l.isOpaque = false
            l.framebufferOnly = true
            // One colour over the whole screen: a tiny drawable, stretched.
            l.drawableSize = CGSize(width: 16, height: 16)
            l.contentsGravity = .resize
            l.frame = view.bounds
            l.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(l)
            p.contentView = view
            panel = p; layer = l
        }
        guard let panel else { return false }
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        if !panel.isVisible {
            panel.orderFrontRegardless()
            SkyLightSpace.shared.attach(panel) // over the lock screen, under the island
        }
        return true
    }

    /// Fills the layer with white at pixel value `v` (linear, 1 = SDR white) and coverage `a`, premultiplied.
    private func draw(_ v: Double, _ a: Double) {
        guard let layer, let queue, let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let c = v * a
        pass.colorAttachments[0].clearColor = MTLClearColor(red: c, green: c, blue: c, alpha: a)
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
