import AppKit

/// Dark Mode (System Events), Night Shift and True Tone (private CoreBrightness). Reads and writes all verified on
/// the owner's Mac in the M10 spike.
@MainActor @Observable
final class DisplayToggles {
    private(set) var darkMode = false
    private(set) var nightShift = false
    private(set) var trueTone = false
    private(set) var trueToneSupported = false
    private(set) var nightShiftSupported = false

    @ObservationIgnored private let blueLight: NSObject?
    @ObservationIgnored private let trueToneClient: NSObject?

    init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        blueLight = (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
        trueToneClient = (NSClassFromString("CBTrueToneClient") as? NSObject.Type)?.init()
    }

    func refresh() {
        darkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        if let c = blueLight {
            let sel = NSSelectorFromString("getBlueLightStatus:")
            if c.responds(to: sel) {
                typealias F = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
                let buf = UnsafeMutableRawPointer.allocate(byteCount: 128, alignment: 8)
                buf.initializeMemory(as: UInt8.self, repeating: 0, count: 128)
                if unsafeBitCast(c.method(for: sel), to: F.self)(c, sel, buf) { nightShift = buf.load(fromByteOffset: 0, as: UInt8.self) != 0; nightShiftSupported = true }
                buf.deallocate()
            }
        }
        if let c = trueToneClient {
            typealias B = @convention(c) (AnyObject, Selector) -> Bool
            func call(_ name: String) -> Bool? {
                let sel = NSSelectorFromString(name)
                return c.responds(to: sel) ? unsafeBitCast(c.method(for: sel), to: B.self)(c, sel) : nil
            }
            trueToneSupported = call("supported") ?? false
            trueTone = call("enabled") ?? false
        }
    }

    func setDarkMode(_ on: Bool) {
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)")?.executeAndReturnError(&err)
        if err == nil { darkMode = on }
    }

    func setNightShift(_ on: Bool) {
        guard let c = blueLight else { return }
        typealias S = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let sel = NSSelectorFromString("setActive:")
        guard c.responds(to: sel) else { return }
        _ = unsafeBitCast(c.method(for: sel), to: S.self)(c, sel, on)
        nightShift = on
    }

    func setTrueTone(_ on: Bool) {
        guard let c = trueToneClient else { return }
        typealias S = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let sel = NSSelectorFromString("setEnabled:")
        guard c.responds(to: sel) else { return }
        _ = unsafeBitCast(c.method(for: sel), to: S.self)(c, sel, on)
        trueTone = on
    }
}
