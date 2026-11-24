import Foundation
import IOKit

/// The SMC through AppleSMC's user client: reading needs nothing, writing needs root (RESEARCH.md "Mac Stats").
final class SMC {
    private var conn: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(conn) }

    /// `SMCKeyData_t`, 80 bytes; the padding keeps Swift's offsets the same as C's.
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

    private static func code(_ s: String) -> UInt32 { s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }

    private func call(_ input: Call) -> Call? {
        var input = input
        var output = Call()
        var size = MemoryLayout<Call>.stride
        return IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<Call>.stride, &output, &size) == KERN_SUCCESS ? output : nil
    }

    private func info(_ key: String) -> Call? {
        var c = Call()
        c.key = Self.code(key)
        c.command = 9
        guard let i = call(c), i.result == 0 else { return nil }
        return i
    }

    func bytes(_ key: String) -> [UInt8]? {
        guard let i = info(key) else { return nil }
        var c = Call()
        c.key = Self.code(key)
        c.size = i.size
        c.command = 5
        guard let r = call(c), r.result == 0 else { return nil }
        return withUnsafeBytes(of: r.bytes) { Array($0.prefix(Int(i.size))) }
    }

    /// `flt` (little-endian), or an unsigned big-endian integer.
    func number(_ key: String) -> Double? {
        guard let i = info(key), let b = bytes(key) else { return nil }
        if i.type == Self.code("flt "), b.count == 4 { return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }) }
        return Double(b.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
    }

    /// True when the SMC took it. Refused without root, and for some keys (a fan's mode) for a few seconds after the
    /// test unlock.
    @discardableResult
    func write(_ key: String, _ data: [UInt8]) -> Bool {
        guard let i = info(key), Int(i.size) == data.count else { return false }
        var c = Call()
        c.key = Self.code(key)
        c.size = i.size
        c.command = 6
        withUnsafeMutableBytes(of: &c.bytes) { for (n, b) in data.enumerated() { $0[n] = b } }
        guard let r = call(c) else { return false }
        return r.result == 0
    }

    func writeFloat(_ key: String, _ value: Double) -> Bool {
        write(key, withUnsafeBytes(of: Float(value)) { Array($0) })
    }

    /// Every key's name by index (`#KEY` holds the count).
    func allKeys() -> [String] {
        guard let n = number("#KEY"), n > 0, n < 20_000 else { return [] }
        return (0..<UInt32(n)).compactMap { index in
            var c = Call()
            c.command = 8
            c.data32 = index
            guard let r = call(c), r.result == 0, r.key != 0 else { return nil }
            return String(bytes: withUnsafeBytes(of: r.key.bigEndian) { Array($0) }, encoding: .ascii)
        }
    }
}
