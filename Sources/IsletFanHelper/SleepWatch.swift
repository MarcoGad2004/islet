import Foundation
import IOKit.pwr_mgt

/// Before sleep, gives the fans back, so the Mac never sleeps or wakes with them held. The power callback is a C
/// function pointer, so what it needs lives here as statics.
enum SleepWatch {
    nonisolated(unsafe) private static var controller: FanController?
    nonisolated(unsafe) private static var rootPort: io_connect_t = 0
    nonisolated(unsafe) private static var notifier: io_object_t = 0
    nonisolated(unsafe) private static var port: IONotificationPortRef?

    /// `iokit_common_msg(0x270)` and `(0x280)`: C macros Swift can't import.
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280

    static func start(_ controller: FanController) {
        self.controller = controller
        rootPort = IORegisterForSystemPower(nil, &port, { _, _, message, argument in
            SleepWatch.handle(message, argument)
        }, &notifier)
        if let port {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        }
    }

    private static func handle(_ message: UInt32, _ argument: UnsafeMutableRawPointer?) {
        switch message {
        case systemWillSleep:
            if let controller { controller.queue.sync { controller.handBack("The Mac went to sleep") } }
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case canSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        default:
            break
        }
    }
}
