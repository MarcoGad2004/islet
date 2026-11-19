import AppKit

/// Sidecar (the iPad as a second display) through the private SidecarCore framework, the same one System Settings and
/// the Screen Mirroring menu use. AirPlay targets (Roku, Apple TV) are not exposed this way.
@MainActor @Observable
final class SidecarController {
    struct Device: Identifiable, Equatable {
        var id: String
        var name: String
        var connected: Bool
    }

    private(set) var devices: [Device] = []
    private(set) var busy: String?
    var error: String?

    @ObservationIgnored private var manager: NSObject?
    @ObservationIgnored private var objects: [String: NSObject] = [:]

    var available: Bool { manager != nil }

    func start() {
        _ = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW)
        guard let cls = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
              cls.responds(to: NSSelectorFromString("sharedManager")),
              let m = cls.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject else { return }
        manager = m
        refresh()
    }

    func refresh() {
        guard let m = manager else { devices = []; return }
        let found = (m.perform(NSSelectorFromString("devices"))?.takeUnretainedValue() as? [NSObject]) ?? []
        let connected = Set(((m.perform(NSSelectorFromString("connectedDevices"))?.takeUnretainedValue() as? [NSObject]) ?? []).map { Self.key($0) })
        objects = [:]
        devices = found.map { d in
            let k = Self.key(d)
            objects[k] = d
            return Device(id: k, name: (d.perform(NSSelectorFromString("name"))?.takeUnretainedValue() as? String) ?? "iPad", connected: connected.contains(k))
        }
    }

    /// Connects (extends the display to the iPad) or disconnects.
    func toggle(_ device: Device) async {
        guard let m = manager, let obj = objects[device.id] else { return }
        busy = device.id; error = nil
        let connect = !device.connected
        nonisolated(unsafe) let mgr = m, dev = obj
        let message: String? = await withCheckedContinuation { cont in
            let block: @convention(block) (AnyObject?) -> Void = { err in
                cont.resume(returning: err.map { ($0 as? NSError)?.localizedDescription ?? "Couldn't reach the iPad." })
            }
            typealias F = @convention(c) (AnyObject, Selector, AnyObject, Any) -> Void
            let sel = NSSelectorFromString(connect ? "connectToDevice:completion:" : "disconnectFromDevice:completion:")
            unsafeBitCast(mgr.method(for: sel), to: F.self)(mgr, sel, dev, block)
        }
        error = message
        busy = nil
        refresh()
    }

    private static func key(_ d: NSObject) -> String { "\(d)" }
}
