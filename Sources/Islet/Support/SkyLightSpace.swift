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
    private typealias RemoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias AddToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
    private var removeWindows: RemoveWindows?
    private var activeSpace: ActiveSpace?
    private var addToSpaces: AddToSpaces?
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
        if let r = dlsym(h, "SLSRemoveWindowsFromSpaces") { removeWindows = unsafeBitCast(r, to: RemoveWindows.self) }
        if let a = dlsym(h, "SLSGetActiveSpace") { activeSpace = unsafeBitCast(a, to: ActiveSpace.self) }
        if let a = dlsym(h, "SLSAddWindowsToSpaces") { addToSpaces = unsafeBitCast(a, to: AddToSpaces.self) }
        isAvailable = true
    }

    /// Moves the window into the lock-screen-level space. Call after the window has been ordered front.
    func attach(_ window: NSWindow) {
        guard isAvailable, window.windowNumber > 0 else { return }
        _ = addWindows?(connection, space, [window.windowNumber] as CFArray, 7)
    }

    /// Back into the desktop's own space for a while: everything in the lock-screen space is drawn over every other
    /// window, whatever its level, so another app's window (Emoji & Symbols) can't come in front of it there.
    /// False when it couldn't be done. `attach` puts it back.
    @discardableResult
    func detach(_ window: NSWindow) -> Bool {
        guard isAvailable, window.windowNumber > 0, let removeWindows, let activeSpace, let addToSpaces else { return false }
        let w = [window.windowNumber] as CFArray
        let desktop = activeSpace(connection)
        guard desktop != 0 else { return false }
        addToSpaces(connection, w, [desktop] as CFArray)
        _ = removeWindows(connection, w, [space] as CFArray)
        return true
    }
}
