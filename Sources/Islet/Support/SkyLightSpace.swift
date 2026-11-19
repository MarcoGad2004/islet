import AppKit

/// Private SkyLight space that sits at the "screen lock" tier, so a window attached to it is drawn over the
/// lock screen. The approach and constants follow the open-source SkyLightWindow library (level 400 is the
/// system's NotificationCenterAtScreenLock). Private API: personal use only, may break on a macOS update.
@MainActor
final class SkyLightSpace {
    static let shared = SkyLightSpace()

    private typealias MainConn = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Show = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private var connection: Int32 = 0
    private var space: Int32 = 0
    private var addWindows: AddWindows?
    private(set) var isAvailable = false

    private init() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let c = dlsym(h, "SLSMainConnectionID"), let cr = dlsym(h, "SLSSpaceCreate"),
              let sl = dlsym(h, "SLSSpaceSetAbsoluteLevel"), let sh = dlsym(h, "SLSShowSpaces"),
              let aw = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return }
        connection = unsafeBitCast(c, to: MainConn.self)()
        space = unsafeBitCast(cr, to: Create.self)(connection, 1, 0)
        _ = unsafeBitCast(sl, to: SetLevel.self)(connection, space, 400)
        _ = unsafeBitCast(sh, to: Show.self)(connection, [space] as CFArray)
        addWindows = unsafeBitCast(aw, to: AddWindows.self)
        isAvailable = true
    }

    /// Moves the window into the lock-screen-level space. Call after the window has been ordered front.
    func attach(_ window: NSWindow) {
        guard isAvailable, window.windowNumber > 0 else { return }
        _ = addWindows?(connection, space, [window.windowNumber] as CFArray, 7)
    }
}
