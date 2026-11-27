import AppKit
import AudioToolbox
import CoreAudio

/// Catches the volume, mute and brightness keys, applies the change itself (16 steps) and publishes it for the
/// island's chin. The keys are consumed so the system display never shows. Needs Accessibility (event tap).
@MainActor @Observable
final class LevelsController {
    struct OutputDevice: Identifiable, Hashable { var id: AudioDeviceID; var name: String }

    private(set) var volume = 0.5
    private(set) var muted = false
    private(set) var brightness = 0.5
    private(set) var brightnessAvailable = false
    /// How far past 100 extended brightness is (0 when off, up to `ExtendedBrightness.maxExtra`).
    private(set) var brightnessExtra = 0.0
    private(set) var keyboard = 0.5
    private(set) var keyboardAvailable = false
    private(set) var outputName = ""
    private(set) var devices: [OutputDevice] = []
    private(set) var tapActive = false

    @ObservationIgnored var onChange: ((LevelState) -> Void)?
    /// Extended brightness turned on or off (the Display page grows its card).
    @ObservationIgnored var onExtendedChange: (() -> Void)?
    @ObservationIgnored fileprivate var tap: CFMachPort?
    @ObservationIgnored private var displayID: CGDirectDisplayID = CGMainDisplayID()
    @ObservationIgnored private let displayServices = DisplayServices()
    @ObservationIgnored private let backlight = KeyboardBacklight()
    /// Brightness to return to after a face scan raised it; nil when nothing is raised.
    @ObservationIgnored private var boostRestore: Double?
    @ObservationIgnored private var rampTask: Task<Void, Never>?
    @ObservationIgnored let extended = ExtendedBrightness()
    /// Brightness-up held at 100: turns extended brightness on after a second unless the key comes up first.
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    /// The press that turned extended brightness on: its repeats are ignored until the key comes up.
    @ObservationIgnored private var swallowRepeats = false
    /// The nudge, hold or unlock showing at 100 (XDR Macs).
    @ObservationIgnored private var cue: XDRCue?

    // MARK: Setup

    func start() {
        refresh()
        installTap()
        watchVolume()
        // Turned off by sleep, lock, low battery or heat: back to 100 on the island too.
        extended.onEnded = { [weak self] in
            guard let self else { return }
            brightnessExtra = 0
            onExtendedChange?()
        }
    }

    /// Retry installing the tap (e.g. after Accessibility was granted).
    func retryTap() { if tap == nil { installTap() } }

    /// Lets the keys go to the system (an update's handoff, while the new copy takes over).
    func stopTap() {
        guard let t = tap else { return }
        CGEvent.tapEnable(tap: t, enable: false)
        CFMachPortInvalidate(t)
        tap = nil
        tapActive = false
    }

    /// The notch screen, when there is one (else the display stays as it was).
    private func resolveDisplay() {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID { displayID = n }
    }

    func refresh() {
        resolveDisplay()
        volume = Double(Audio.volume() ?? 0.5)
        muted = Audio.muted() ?? false
        if let b = displayServices.get(displayID) { brightness = Double(b); brightnessAvailable = true } else { brightnessAvailable = false }
        if let k = backlight.get() { keyboard = Double(k); keyboardAvailable = true } else { keyboardAvailable = false }
        devices = Audio.outputDevices().map { OutputDevice(id: $0.0, name: $0.1) }
        outputName = Audio.defaultOutput().flatMap { id in devices.first { $0.id == id }?.name } ?? ""
    }

    // MARK: Volume changed elsewhere

    /// The volume listeners on the current output device, to take them off when the output changes.
    @ObservationIgnored private var watchedDevice: AudioDeviceID?
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?

    /// Volume changed by anything but the keys (AirPods' own controls, Control Center, the menu bar, another app, the
    /// iPhone): the island shows it too. Changes Islet made itself are recognised by matching what it last set.
    private func watchVolume() {
        var a = Audio.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A new output (AirPods connecting): take its volume quietly, then follow it.
                self.refresh()
                self.watchOutputDevice()
            }
        }
        watchOutputDevice()
    }

    private func watchOutputDevice() {
        if let old = watchedDevice, let block = deviceListener {
            for var a in Audio.volumeAddresses { AudioObjectRemovePropertyListenerBlock(old, &a, .main, block) }
        }
        watchedDevice = nil; deviceListener = nil
        guard let dev = Audio.defaultOutput() else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.volumeChangedElsewhere() }
        }
        for var a in Audio.volumeAddresses where AudioObjectHasProperty(dev, &a) {
            AudioObjectAddPropertyListenerBlock(dev, &a, .main, block)
        }
        watchedDevice = dev; deviceListener = block
    }

    private func volumeChangedElsewhere() {
        guard let v = Audio.volume().map(Double.init) else { return }
        let m = Audio.muted() ?? muted
        // Bluetooth outputs round what they're given (AirPods have 128 steps), so a change Islet made reads back a
        // little off; real changes are at least a step of 1/128.
        let changed = abs(v - volume) > 0.005 || m != muted
        volume = v; muted = m
        guard changed, Feature.levels.isOn else { return }
        onChange?(LevelState(kind: .volume, value: v, muted: m))
    }

    // MARK: Event tap

    private func installTap() {
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<LevelsController>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) } }
                return Unmanaged.passUnretained(event)
            }
            let consumed = MainActor.assumeIsolated { me.handle(event) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { tapActive = false; return }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tapActive = true
    }

    /// Returns true when the event was ours and must not reach the system.
    private func handle(_ cg: CGEvent) -> Bool {
        // Turned off (Settings > Islet, Features): the keys go to macOS's own display.
        guard Feature.levels.isOn else { return false }
        guard let ns = NSEvent(cgEvent: cg), ns.type == .systemDefined, ns.subtype.rawValue == 8 else { return false }
        let key = (ns.data1 & 0xFFFF0000) >> 16
        let flags = ns.data1 & 0x0000FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0xA
        let isRepeat = flags & 0x1 != 0
        // Option + Shift: quarter steps (64 instead of 16), like the system's fine adjustment.
        let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
        // NX_KEYTYPE: 0 sound up, 1 sound down, 7 mute, 2 brightness up, 3 brightness down,
        // 21 keyboard backlight up, 22 down, 23 toggle (Macs with backlight keys on the top row)
        switch key {
        case 0, 1, 7:
            guard Audio.volume() != nil else { return false } // output without software volume: let the system handle it
            if isDown { volumeKey(key, fine: fine) }
            return true
        case 2, 3:
            // No display DisplayServices can drive (lid closed with only an external screen): macOS keeps the key.
            resolveDisplay()
            guard displayServices.available, displayServices.get(displayID) != nil else { return false }
            if isDown { brightnessKey(up: key == 2, fine: fine, isRepeat: isRepeat) } else { brightnessKeyUp() }
            return true
        case 21, 22, 23:
            guard backlight.get() != nil else { return false }
            if isDown { keyboardKey(key, fine: fine) }
            return true
        default:
            return false
        }
    }

    private func volumeKey(_ key: Int, fine: Bool) {
        var v = Double(Audio.volume() ?? 0)
        // Outputs with no mute switch (many Bluetooth, HDMI and USB ones) are muted by taking the volume to 0.
        let hardMute = Audio.muted() != nil
        var m = Audio.muted() ?? muted
        let n = fine ? 64.0 : 16.0
        let step = (v * n).rounded()
        switch key {
        case 0: v = min(n, step + 1) / n; if m { m = false }
        case 1: v = max(0, step - 1) / n
        default:
            m.toggle()
            if !hardMute { v = softMute(m, current: v) }
        }
        Audio.setVolume(Float(v))
        Audio.setMuted(m)
        volume = v; muted = m
        onChange?(LevelState(kind: .volume, value: v, muted: m || v == 0 && key == 7))
    }

    private func brightnessKey(up: Bool, fine: Bool, isRepeat: Bool) {
        // The owner took over: stop any face-scan ramp and keep whatever they choose.
        rampTask?.cancel(); boostRestore = nil
        let n = fine ? 64.0 : 16.0
        if isRepeat && swallowRepeats { return }

        // Extended brightness (XDR): the extra goes first, in the same steps as the bar; at 0 it's off and 100 stays.
        if extended.isOn {
            let e = brightnessExtra
            let next = up ? min(ExtendedBrightness.maxExtra, ((e * n + 1e-6).rounded(.down) + 1) / n)
                          : ((e * n - 1e-6).rounded(.up) - 1) / n
            brightnessExtra = extended.set(next)
            cue = nil
            if brightnessExtra == 0 { onExtendedChange?() }
            onChange?(LevelState(kind: .brightness, value: 1, extra: brightnessExtra))
            return
        }

        let step = ((displayServices.get(displayID).map(Double.init) ?? brightness) * n).rounded()
        let b = (up ? min(n, step + 1) : max(0, step - 1)) / n
        displayServices.set(displayID, Float(b))
        brightness = b

        if up, b >= 1, extended.mayStart {
            if step >= n {
                // Already at 100: holding for a second unlocks extended brightness; the bar fills meanwhile.
                if holdTask == nil {
                    cue = XDRCue(kind: .charging, since: Date())
                    holdTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(XDRCue.holdSeconds))
                        guard let self, !Task.isCancelled else { return }
                        holdTask = nil
                        swallowRepeats = true
                        brightnessExtra = extended.set(1 / 16)
                        cue = brightnessExtra > 0 ? XDRCue(kind: .unlocked, since: Date()) : nil
                        onExtendedChange?()
                        onChange?(LevelState(kind: .brightness, value: 1, extra: brightnessExtra, cue: cue))
                    }
                }
            } else {
                // Just reached 100: the nudge.
                cue = XDRCue(kind: .nudge, since: Date())
            }
        } else {
            cue = nil
        }
        onChange?(LevelState(kind: .brightness, value: b, cue: cue))
    }

    private func brightnessKeyUp() {
        swallowRepeats = false
        guard let task = holdTask else { return }
        // Let go too soon: the fill drains and the hint says to hold.
        task.cancel(); holdTask = nil
        cue = XDRCue(kind: .nudge, since: Date().addingTimeInterval(-XDRCue.hintDelay + 0.25))
        onChange?(LevelState(kind: .brightness, value: brightness, cue: cue))
    }

    /// Remembered by the toggle key so a second press brings the backlight back where it was.
    @ObservationIgnored private var keyboardBeforeOff: Double?

    private func keyboardKey(_ key: Int, fine: Bool) {
        let n = fine ? 64.0 : 16.0
        let now = backlight.get().map(Double.init) ?? keyboard
        var k: Double
        switch key {
        case 21: k = min(n, (now * n).rounded() + 1) / n
        case 22: k = max(0, (now * n).rounded() - 1) / n
        default:
            if now > 0 { keyboardBeforeOff = now; k = 0 } else { k = keyboardBeforeOff ?? 0.5 }
        }
        if key != 23 { keyboardBeforeOff = nil }
        backlight.set(Float(k))
        keyboard = k
        onChange?(LevelState(kind: .keyboard, value: k))
    }

    // MARK: Sliders and output picker (expanded panel)

    func setVolume(_ v: Double) {
        Audio.setVolume(Float(v)); volume = v
        if muted && v > 0 { Audio.setMuted(false); muted = false }
    }

    func toggleMute() {
        let m = !muted
        if Audio.muted() == nil {
            let v = softMute(m, current: volume)
            Audio.setVolume(Float(v)); volume = v
        } else {
            Audio.setMuted(m)
        }
        muted = m
    }

    /// The volume before a software mute (outputs without a mute switch), to come back to.
    @ObservationIgnored private var volumeBeforeMute: Double?

    /// Mutes by taking the volume to 0, or restores it. Returns the volume to set.
    private func softMute(_ on: Bool, current v: Double) -> Double {
        if on { volumeBeforeMute = v > 0 ? v : volumeBeforeMute; return 0 }
        defer { volumeBeforeMute = nil }
        return volumeBeforeMute ?? 0.5
    }

    func setBrightness(_ b: Double) {
        rampTask?.cancel(); boostRestore = nil
        // The slider covers 0...100: moving it leaves extended brightness.
        if extended.isOn { extended.stop(); brightnessExtra = 0; onExtendedChange?() }
        displayServices.set(displayID, Float(b)); brightness = b
    }

    /// The Display page's Turn Off: back to 100.
    func endExtendedBrightness() {
        guard extended.isOn else { return }
        extended.stop(); brightnessExtra = 0; onExtendedChange?()
    }

    func setKeyboard(_ k: Double) {
        backlight.set(Float(k)); keyboard = k; keyboardBeforeOff = nil
    }

    // MARK: Face scan light

    /// Face unlock in a dark room: ease the screen up so it lights the face. Does nothing when already raised
    /// or the screen is already at least that bright.
    func boostForFaceScan(to target: Double = 1.0, over seconds: Double = 1.4) {
        guard boostRestore == nil, displayServices.available, let now = displayServices.get(displayID).map(Double.init),
              now < target - 0.02 else { return }
        boostRestore = now
        ramp(from: now, to: target, over: seconds)
    }

    /// Ease back to the brightness from before the scan.
    func endFaceScanBoost(over seconds: Double = 1.0, immediately: Bool = false) {
        guard let restore = boostRestore else { return }
        boostRestore = nil
        if immediately {
            rampTask?.cancel()
            displayServices.set(displayID, Float(restore)); brightness = restore
            return
        }
        let now = displayServices.get(displayID).map(Double.init) ?? brightness
        ramp(from: now, to: restore, over: seconds)
    }

    /// Face unlock's depth check where the glow can't be drawn (FaceGlow): one smooth swell of the screen brightness and back (never a flicker). It brightens
    /// by `change` when there's room, and dims by it when the screen is already bright. Waits for a dark-room ramp to
    /// finish first. Returns when the ramp up started and which way it went, or nil when brightness can't be set.
    /// `onStart` runs as the swell begins, so the scan can judge it at its peak.
    func pulseForFaceScan(change: Double = FacePulse.change,
                          onStart: (FacePulse.Schedule) -> Void = { _ in }) async -> FacePulse.Schedule? {
        await rampTask?.value
        guard displayServices.available, let now = displayServices.get(displayID).map(Double.init) else { return nil }
        let up = now <= 1 - change
        let target = up ? now + change : now - change
        let start = Date()
        onStart(FacePulse.Schedule.swell(start: start, brighter: up))
        ramp(from: now, to: target, over: FacePulse.rise)
        await rampTask?.value
        try? await Task.sleep(for: .seconds(FacePulse.hold))
        // A brightness key pressed during the pulse cancels it and wins.
        if let current = displayServices.get(displayID).map(Double.init), abs(current - target) < 0.02 {
            ramp(from: target, to: now, over: FacePulse.fall)
            await rampTask?.value
        }
        return FacePulse.Schedule.swell(start: start, brighter: up)
    }

    private func ramp(from a: Double, to b: Double, over seconds: Double) {
        rampTask?.cancel()
        let display = displayID, services = displayServices
        rampTask = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let t = min(Date().timeIntervalSince(start) / seconds, 1)
                let e = t * t * (3 - 2 * t) // ease in and out
                let v = a + (b - a) * e
                services.set(display, Float(v))
                self?.brightness = v
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func selectOutput(_ device: OutputDevice) {
        Audio.setDefaultOutput(device.id)
        refresh()
    }
}

// MARK: - Brightness (private DisplayServices, resolved at runtime)

private struct DisplayServices {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let getFn: Get?
    private let setFn: Set?

    init() {
        let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getFn = h.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
        setFn = h.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }
    }

    var available: Bool { getFn != nil && setFn != nil }

    func get(_ display: CGDirectDisplayID) -> Float? {
        var v: Float = 0
        guard let getFn, getFn(display, &v) == 0 else { return nil }
        return v
    }

    @discardableResult func set(_ display: CGDirectDisplayID, _ v: Float) -> Bool { setFn?(display, v) == 0 }
}

// MARK: - Keyboard backlight (private CoreBrightness KeyboardBrightnessClient, resolved at runtime)

/// The built-in keyboard's backlight, 0...1. `get()` is nil on Macs without one (or if the private class changes).
private struct KeyboardBacklight {
    private let client: NSObject?

    init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        client = (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }

    /// The first keyboard with a backlight, preferring the built-in one.
    private var keyboardID: UInt64? {
        guard let c = client else { return nil }
        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard c.responds(to: idsSel), let ids = c.perform(idsSel)?.takeRetainedValue() as? [NSNumber], !ids.isEmpty else { return nil }
        let builtInSel = NSSelectorFromString("isKeyboardBuiltIn:")
        if c.responds(to: builtInSel) {
            typealias B = @convention(c) (AnyObject, Selector, UInt64) -> Bool
            let f = unsafeBitCast(c.method(for: builtInSel), to: B.self)
            if let id = ids.first(where: { f(c, builtInSel, $0.uint64Value) }) { return id.uint64Value }
        }
        return ids[0].uint64Value
    }

    func get() -> Float? {
        guard let c = client, let id = keyboardID else { return nil }
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard c.responds(to: sel) else { return nil }
        typealias G = @convention(c) (AnyObject, Selector, UInt64) -> Float
        return min(max(unsafeBitCast(c.method(for: sel), to: G.self)(c, sel, id), 0), 1)
    }

    func set(_ v: Float) {
        guard let c = client, let id = keyboardID else { return }
        let value = min(max(v, 0), 1)
        // The committing form saves the level the way Control Center does; the plain one is the fallback.
        let commit = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
        if c.responds(to: commit) {
            typealias S = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
            _ = unsafeBitCast(c.method(for: commit), to: S.self)(c, commit, value, 0, true, id)
            return
        }
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard c.responds(to: sel) else { return }
        typealias S = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        _ = unsafeBitCast(c.method(for: sel), to: S.self)(c, sel, value, id)
    }
}

// MARK: - CoreAudio helpers

private enum Audio {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// The output's volume and mute, which the island follows.
    static var volumeAddresses: [AudioObjectPropertyAddress] {
        [address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput),
         address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)]
    }

    static func defaultOutput() -> AudioDeviceID? {
        var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func setDefaultOutput(_ id: AudioDeviceID) {
        var d = id; var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &d)
    }

    static func volume() -> Float? {
        guard let dev = defaultOutput() else { return nil }
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(dev, &a) else { return nil }
        var v: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func setVolume(_ v: Float) {
        guard let dev = defaultOutput() else { return }
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
        var value = min(max(v, 0), 1)
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func muted() -> Bool? {
        guard let dev = defaultOutput() else { return nil }
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(dev, &a) else { return nil }
        var m: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &m) == noErr ? m != 0 : nil
    }

    static func setMuted(_ m: Bool) {
        guard let dev = defaultOutput() else { return }
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(dev, &a) else { return }
        var value: UInt32 = m ? 1 : 0
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func outputDevices() -> [(AudioDeviceID, String)] {
        var a = address(kAudioHardwarePropertyDevices); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var s = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput); var n: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &s, 0, nil, &n) == noErr, n > 0 else { return nil }
            var na = address(kAudioObjectPropertyName); var name: Unmanaged<CFString>?; var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &na, 0, nil, &ns, &name) == noErr, let n = name?.takeRetainedValue() else { return nil }
            return (id, n as String)
        }
    }
}
