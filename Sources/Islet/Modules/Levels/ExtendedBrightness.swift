import AppKit
import IOKit.ps
import Metal
import QuartzCore
import os

/// Extended brightness (1.7, owner request 2026-11-24): on a MacBook Pro's XDR panel, the whole desktop past macOS's
/// SDR limit, up to 160. Holding brightness-up for a second at 100 turns it on (LevelsController).
///
/// How (the technique BrightIntosh uses): a 1 x 1 pt window in the screen's top-left corner shows an EDR pixel above
/// SDR white, so macOS puts the display in EDR mode and leaves headroom above SDR white; then the display's gamma table
/// is scaled by the factor, so SDR white lands above 1.0 and the whole desktop goes brighter. Off, the system's colour
/// settings come back (`CGDisplayRestoreColorSyncSettings`); macOS also undoes the table if the app quits or crashes.
///
/// It's turned off (never just paused) when the screen sleeps or locks, the display changes, the battery is low or the
/// Mac gets hot, and it never survives a restart.
@MainActor
final class ExtendedBrightness {
    static let enabledKey = "extendedBrightness"
    private static let log = Logger(subsystem: "com.marcogad.islet", category: "levels")

    /// The most it adds: 160 on the island's scale.
    static let maxExtra = 0.6
    /// The EDR pixel's value, above any factor used.
    private static let triggerValue = 1.7

    /// On in Settings (default on).
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// 0 when off, else how far past 100 it is (0...maxExtra, 0.6 = 160).
    private(set) var extra = 0.0
    var isOn: Bool { extra > 0 }

    /// Called when it turns itself off (sleep, lock, low battery, heat), so the island's level can follow.
    var onEnded: (() -> Void)?

    /// Made on first use: Metal isn't loaded at launch, nor at all on Macs without an XDR panel.
    private lazy var device = MTLCreateSystemDefaultDevice()
    private lazy var queue = device?.makeCommandQueue()
    private var panel: NSPanel?
    private var layer: CAMetalLayer?
    private var displayID: CGDirectDisplayID = 0
    /// The table before it was scaled.
    private var base: (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])?
    /// The factor now in the table.
    private var applied = 1.0
    private var fade: Task<Void, Never>?
    private var keepUp: Timer?
    private var observers: [NSObjectProtocol] = []
    private var reconfigRegistered = false

    // MARK: Support

    private static var builtIn: (screen: NSScreen, id: CGDirectDisplayID)? {
        for s in NSScreen.screens {
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDisplayIsBuiltin(n.uint32Value) != 0 else { continue }
            return (s, n.uint32Value)
        }
        return nil
    }

    /// The built-in screen is an XDR panel (it can show EDR well past SDR white) and Metal is there.
    static var isSupported: Bool {
        guard let b = builtIn else { return false }
        return b.screen.maximumPotentialExtendedDynamicRangeColorComponentValue >= 2
    }

    /// Whether it may turn on now: enabled, supported, the screen awake, not low on battery, not hot.
    var mayStart: Bool {
        guard Self.isEnabled, Self.isSupported, let b = Self.builtIn, CGDisplayIsAsleep(b.id) == 0 else { return false }
        return !Self.tooHot && !Self.lowBattery
    }

    private static var tooHot: Bool {
        let t = ProcessInfo.processInfo.thermalState
        return t == .serious || t == .critical
    }

    /// On battery and under 20 %.
    private static var lowBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 100, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return !onAC && max > 0 && cur * 100 / max < 20
        }
        return false
    }

    // MARK: On, off, level

    /// Sets how far past 100 it is, turning it on or off as needed. Returns the extra it ended at.
    @discardableResult
    func set(_ newExtra: Double) -> Double {
        let e = min(max(newExtra, 0), Self.maxExtra)
        if e <= 0.0005 { stop(); return 0 }
        if !isOn {
            guard mayStart, start() else { return 0 }
        }
        extra = e
        fadeTo(1 + e)
        return e
    }

    /// Off, easing back to 100.
    func stop(animated: Bool = true) {
        guard isOn || panel?.isVisible == true else { return }
        extra = 0
        keepUp?.invalidate(); keepUp = nil
        fade?.cancel()
        if animated, applied > 1.001 {
            let from = applied
            fade = Task { [weak self] in
                await self?.ramp(from: from, to: 1)
                guard let self, !Task.isCancelled, !self.isOn else { return }
                self.tearDown()
            }
        } else {
            tearDown()
        }
    }

    /// Turned off by something other than the keys: tells the island.
    private func end(_ why: String) {
        guard isOn else { return }
        Self.log.notice("extended brightness off: \(why, privacy: .public)")
        stop()
        onEnded?()
    }

    private func start() -> Bool {
        guard let device, let b = Self.builtIn else { return false }
        displayID = b.id
        guard let table = readTable() else { return false }
        base = table
        applied = 1
        showTrigger(on: b.screen, device: device)
        watch()
        keepUp?.invalidate()
        keepUp = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        Self.log.notice("extended brightness on (headroom \(b.screen.maximumExtendedDynamicRangeColorComponentValue))")
        return true
    }

    private func tearDown() {
        fade?.cancel(); fade = nil
        keepUp?.invalidate(); keepUp = nil
        CGDisplayRestoreColorSyncSettings()
        applied = 1
        base = nil
        panel?.orderOut(nil)
        unwatch()
    }

    /// Every second while on: keep the EDR pixel drawn, put the table back if something reset it, and give up
    /// when the battery or the heat says so.
    private func tick() {
        guard isOn else { return }
        if Self.tooHot { end("thermal pressure"); return }
        if Self.lowBattery { end("battery low"); return }
        drawTrigger()
        guard fade == nil || fade!.isCancelled, let base else { return }
        // Read back an entry that stays under 1.0 when scaled (the readback clamps at 1.0).
        let i = base.r.count / 4
        if let now = readTable(), i < now.r.count, abs(Double(now.r[i]) - Double(base.r[i]) * applied) > 0.003 {
            apply(applied)
        }
    }

    // MARK: Gamma table

    private func readTable() -> (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])? {
        let cap: UInt32 = 256
        var r = [CGGammaValue](repeating: 0, count: Int(cap)), g = r, b = r
        var n: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, cap, &r, &g, &b, &n) == .success, n > 1 else { return nil }
        return (Array(r.prefix(Int(n))), Array(g.prefix(Int(n))), Array(b.prefix(Int(n))))
    }

    private func apply(_ factor: Double) {
        guard let base else { return }
        let f = CGGammaValue(factor)
        var r = base.r.map { $0 * f }, g = base.g.map { $0 * f }, b = base.b.map { $0 * f }
        if CGSetDisplayTransferByTable(displayID, UInt32(r.count), &r, &g, &b) == .success { applied = factor }
    }

    private func fadeTo(_ factor: Double) {
        fade?.cancel()
        let from = applied
        fade = Task { [weak self] in
            // Wait for the EDR headroom (it climbs over ~1 s once the pixel shows), so nothing clips on the way up.
            let wait = Date().addingTimeInterval(1.5)
            while let b = Self.builtIn, Double(b.screen.maximumExtendedDynamicRangeColorComponentValue) < factor * 0.98,
                  Date() < wait, !Task.isCancelled {
                self?.drawTrigger()
                try? await Task.sleep(for: .milliseconds(50))
            }
            await self?.ramp(from: from, to: factor)
            self?.fade = nil
        }
    }

    /// Eases the table between two factors over 0.25 s.
    private func ramp(from a: Double, to b: Double) async {
        let start = Date(), seconds = 0.25
        while !Task.isCancelled {
            let t = min(Date().timeIntervalSince(start) / seconds, 1)
            apply(a + (b - a) * t * t * (3 - 2 * t))
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    // MARK: EDR pixel

    private func showTrigger(on screen: NSScreen, device: MTLDevice) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.ignoresMouseEvents = true
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            view.wantsLayer = true
            let l = CAMetalLayer()
            l.device = device
            l.pixelFormat = .rgba16Float
            l.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            l.wantsExtendedDynamicRangeContent = true
            l.isOpaque = false
            l.drawableSize = CGSize(width: 1, height: 1)
            l.frame = view.bounds
            view.layer?.addSublayer(l)
            p.contentView = view
            panel = p; layer = l
        }
        // The top-left corner, under the menu bar.
        panel?.setFrameOrigin(NSPoint(x: screen.frame.minX, y: screen.frame.maxY - 1))
        panel?.orderFrontRegardless()
        drawTrigger()
    }

    private func drawTrigger() {
        guard let layer, let queue, let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let v = Self.triggerValue
        pass.colorAttachments[0].clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: 1)
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    // MARK: Sleep, lock, display changes

    private func watch() {
        guard observers.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        let off: [(NotificationCenter, Notification.Name, String)] = [
            (ws, NSWorkspace.screensDidSleepNotification, "screens slept"),
            (ws, NSWorkspace.willSleepNotification, "Mac sleeping"),
            (ws, NSWorkspace.sessionDidResignActiveNotification, "session switched"),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"), "screen locked"),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screensaver.didstart"), "screen saver"),
            (NotificationCenter.default, NSApplication.willTerminateNotification, "quitting"),
        ]
        for (center, name, why) in off {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end(why) }
            })
        }
        // This one also fires when the EDR headroom moves (which the pixel itself causes), so only a lost built-in
        // screen (lid closed) ends it.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Self.builtIn?.id != self.displayID { self.end("built-in display gone") }
            }
        })
        if !reconfigRegistered {
            reconfigRegistered = true
            // A new mode, mirroring or the built-in display going away resets the table: end rather than fight it.
            CGDisplayRegisterReconfigurationCallback({ display, flags, info in
                let real: CGDisplayChangeSummaryFlags = [.setModeFlag, .removeFlag, .disabledFlag, .mirrorFlag]
                guard !flags.contains(.beginConfigurationFlag), !flags.isDisjoint(with: real),
                      CGDisplayIsBuiltin(display) != 0, let info else { return }
                let me = Unmanaged<ExtendedBrightness>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { me.end("display reconfigured") } }
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func unwatch() {
        for o in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            DistributedNotificationCenter.default().removeObserver(o)
            NotificationCenter.default.removeObserver(o)
        }
        observers = []
    }
}
