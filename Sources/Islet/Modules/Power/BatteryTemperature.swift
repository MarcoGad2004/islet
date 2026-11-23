import Foundation
import IOKit

/// The battery's temperature from the SMC. macOS no longer puts it in the battery's registry entry, but the SMC's
/// battery sensors (`TB0T`, `TB1T`, `TB2T`, floats in °C) can be read by any app through AppleSMC's user client.
enum BatteryTemperature {
    /// The mean of the battery sensors that answer, in °C; nil when none do (a Mac without a battery).
    static func read() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conn) }
        let readings = ["TB0T", "TB1T", "TB2T"].compactMap { value(conn, key: $0) }.filter { $0 > 0 && $0 < 100 }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    /// The SMC's call layout (`SMCKeyData_t`, 80 bytes). The padding keeps Swift's field offsets the same as C's.
    private struct Call {
        var key: UInt32 = 0
        var version: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var limits: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var size: UInt32 = 0
        var type: UInt32 = 0
        var attributes: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private static let readKeyInfo: UInt8 = 9
    private static let readBytes: UInt8 = 5

    private static func value(_ conn: io_connect_t, key: String) -> Double? {
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        var info = Call()
        info.key = code
        info.command = readKeyInfo
        guard let i = call(conn, info), i.result == 0, i.size > 0 else { return nil }
        var read = Call()
        read.key = code
        read.size = i.size
        read.command = readBytes
        guard let r = call(conn, read), r.result == 0 else { return nil }
        let bytes = withUnsafeBytes(of: r.bytes) { Array($0.prefix(Int(i.size))) }
        switch i.type {
        case fourCC("flt ") where bytes.count == 4:
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case fourCC("sp78") where bytes.count == 2:
            // Signed fixed point, 8 fraction bits, big-endian.
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }

    private static func call(_ conn: io_connect_t, _ input: Call) -> Call? {
        var input = input
        var output = Call()
        var size = MemoryLayout<Call>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<Call>.stride, &output, &size)
        return r == KERN_SUCCESS ? output : nil
    }
}
