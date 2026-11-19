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
    private(set) var outputName = ""
    private(set) var devices: [OutputDevice] = []
    private(set) var tapActive = false

    @ObservationIgnored var onChange: ((LevelState) -> Void)?
    @ObservationIgnored fileprivate var tap: CFMachPort?
    @ObservationIgnored private var displayID: CGDirectDisplayID = CGMainDisplayID()
    @ObservationIgnored private let displayServices = DisplayServices()

    // MARK: Setup

    func start() {
        refresh()
        installTap()
    }

    /// Retry installing the tap (e.g. after Accessibility was granted).
    func retryTap() { if tap == nil { installTap() } }

    func refresh() {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID { displayID = n }
        volume = Double(Audio.volume() ?? 0.5)
        muted = Audio.muted() ?? false
        if let b = displayServices.get(displayID) { brightness = Double(b); brightnessAvailable = true } else { brightnessAvailable = false }
        devices = Audio.outputDevices().map { OutputDevice(id: $0.0, name: $0.1) }
        outputName = Audio.defaultOutput().flatMap { id in devices.first { $0.id == id }?.name } ?? ""
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
        guard let ns = NSEvent(cgEvent: cg), ns.type == .systemDefined, ns.subtype.rawValue == 8 else { return false }
        let key = (ns.data1 & 0xFFFF0000) >> 16
        let flags = ns.data1 & 0x0000FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0xA
        // NX_KEYTYPE: 0 sound up, 1 sound down, 7 mute, 2 brightness up, 3 brightness down
        switch key {
        case 0, 1, 7:
            guard Audio.volume() != nil else { return false } // output without software volume: let the system handle it
            if isDown { volumeKey(key) }
            return true
        case 2, 3:
            guard displayServices.available else { return false }
            if isDown { brightnessKey(up: key == 2) }
            return true
        default:
            return false
        }
    }

    private func volumeKey(_ key: Int) {
        var v = Double(Audio.volume() ?? 0)
        var m = Audio.muted() ?? false
        let step = (v * 16).rounded()
        switch key {
        case 0: v = min(16, step + 1) / 16; if m { m = false }
        case 1: v = max(0, step - 1) / 16
        default: m.toggle()
        }
        Audio.setVolume(Float(v))
        Audio.setMuted(m)
        volume = v; muted = m
        onChange?(LevelState(kind: .volume, value: v, muted: m || v == 0 && key == 7))
    }

    private func brightnessKey(up: Bool) {
        let step = ((displayServices.get(displayID).map(Double.init) ?? brightness) * 16).rounded()
        let b = (up ? min(16, step + 1) : max(0, step - 1)) / 16
        displayServices.set(displayID, Float(b))
        brightness = b
        onChange?(LevelState(kind: .brightness, value: b))
    }

    // MARK: Sliders and output picker (expanded panel)

    func setVolume(_ v: Double) {
        Audio.setVolume(Float(v)); volume = v
        if muted && v > 0 { Audio.setMuted(false); muted = false }
    }

    func setBrightness(_ b: Double) { displayServices.set(displayID, Float(b)); brightness = b }

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

// MARK: - CoreAudio helpers

private enum Audio {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
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
