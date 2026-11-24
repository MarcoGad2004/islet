import Foundation
import IOKit

/// Live readings from the SMC, through AppleSMC's user client (any app can read it; writing needs root, RESEARCH.md
/// "Mac Stats"). The battery's registry entry only
/// refreshes about every 30 s; the SMC's power sensors change every second (RESEARCH.md "Battery stats").
enum SMCSensors {
    /// The battery's temperature in °C: the mean of its sensors (`TB0T`, `TB1T`, `TB2T`) that answer. macOS no longer
    /// puts it in the battery's registry entry.
    static func temperature() -> Double? {
        session { conn in
            let readings = ["TB0T", "TB1T", "TB2T"].compactMap { value(conn, key: $0) }.filter { $0 > 0 && $0 < 100 }
            guard !readings.isEmpty else { return nil }
            return readings.reduce(0, +) / Double(readings.count)
        }
    }

    struct Power: Equatable {
        /// What the whole Mac is drawing (`PSTR`).
        var system: Double
        /// What the charger is delivering (`PDTR`); 0 without one.
        var chargerIn: Double?
        /// Into the battery (+) or out of it (-) (`SBAP`, which the SMC signs the other way).
        var battery: Double?
    }

    static func power() -> Power? {
        session { conn in
            guard let system = value(conn, key: "PSTR"), system >= 0 else { return nil }
            return Power(system: system, chargerIn: value(conn, key: "PDTR").map { max(0, $0) },
                         battery: value(conn, key: "SBAP").map { -$0 })
        }
    }

    /// Every key's name, by index (`#KEY` holds the count; about 3,400 on an M4 Pro). Slow-ish: read once and keep.
    static func allKeys() -> [String] {
        session { conn -> [String]? in
            guard let count = value(conn, key: "#KEY"), count > 0, count < 20_000 else { return nil }
            return (0..<UInt32(count)).compactMap { key(conn, at: $0) }
        } ?? []
    }

    /// The keys that answer with a number (`flt`, `sp78`, `ui8`, `ui16`, `ui32`), read in one session.
    static func values(_ keys: [String]) -> [String: Double] {
        session { conn -> [String: Double]? in
            var out: [String: Double] = [:]
            for k in keys { if let v = value(conn, key: k) { out[k] = v } }
            return out
        } ?? [:]
    }

    private static func session<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conn) }
        return body(conn)
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
    private static let readKeyAtIndex: UInt8 = 8

    private static func key(_ conn: io_connect_t, at index: UInt32) -> String? {
        var c = Call()
        c.command = readKeyAtIndex
        c.data32 = index
        guard let r = call(conn, c), r.result == 0, r.key != 0 else { return nil }
        return String(bytes: withUnsafeBytes(of: r.key.bigEndian) { Array($0) }, encoding: .ascii)
    }

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
        case fourCC("ui8 "), fourCC("ui16"), fourCC("ui32"):
            // Unsigned, big-endian.
            return Double(bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
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
