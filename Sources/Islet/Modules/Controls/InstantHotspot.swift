import Foundation

/// A phone offering its Personal Hotspot through Instant Hotspot. These come from sharingd over Bluetooth, not from a
/// Wi-Fi scan (the phone only starts broadcasting once asked), which is why CoreWLAN never lists them.
struct InstantHotspot: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// 0...4 bars of cellular signal.
    var bars: Int
    var battery: Int?
    fileprivate var device: SendableObject

    static func == (a: InstantHotspot, b: InstantHotspot) -> Bool {
        a.id == b.id && a.name == b.name && a.bars == b.bars && a.battery == b.battery
    }
}

/// The private SFRemoteHotspotDevice, carried across threads; only sharingd's own objects ever go in here.
fileprivate struct SendableObject: @unchecked Sendable { let object: NSObject }

/// Browses for Instant Hotspot phones and asks one to turn its hotspot on, through Sharing.framework's private
/// SFRemoteHotspotSession (what Control Center and Wi-Fi Settings use). Needs no entitlement. Browsing uses
/// Bluetooth, so it runs only while the Wi-Fi panel wants it.
@MainActor
final class InstantHotspotBrowser: NSObject {
    var onChange: (([InstantHotspot]) -> Void)?
    private var session: NSObject?
    private let receiver = Receiver()

    override init() {
        super.init()
        receiver.onDevices = { [weak self] list in Task { @MainActor in self?.onChange?(list) } }
    }

    private static let available: Bool = {
        dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_NOW)
        guard let cls = NSClassFromString("SFRemoteHotspotSession") else { return false }
        return [#selector(Receiver.setDelegate(_:)), NSSelectorFromString("startBrowsing"), NSSelectorFromString("stopBrowsing"),
                NSSelectorFromString("enableHotspotForDevice:withCompletionHandler:")]
            .allSatisfy { cls.instancesRespond(to: $0) }
    }()

    func start() {
        guard session == nil, Self.available, let cls = NSClassFromString("SFRemoteHotspotSession") as? NSObject.Type else { return }
        let s = cls.init()
        s.perform(#selector(Receiver.setDelegate(_:)), with: receiver)
        s.perform(NSSelectorFromString("startBrowsing"))
        session = s
    }

    func stop() {
        session?.perform(NSSelectorFromString("stopBrowsing"))
        session = nil
        onChange?([])
    }

    /// Asks the phone to turn its hotspot on; macOS then joins it by itself. Returns false if it couldn't ask.
    func enable(_ h: InstantHotspot) -> Bool {
        let sel = NSSelectorFromString("enableHotspotForDevice:withCompletionHandler:")
        guard let s = session, s.responds(to: sel) else { return false }
        typealias Enable = @convention(c) (NSObject, Selector, NSObject, @convention(block) () -> Void) -> Void
        let imp = unsafeBitCast(s.method(for: sel), to: Enable.self)
        // The handler's arguments aren't known, so it takes none (extra ones are ignored); success shows up as the
        // Wi-Fi network changing.
        imp(s, sel, h.device.object, {})
        return true
    }

    /// The session's delegate. sharingd calls `session:updatedFoundDevices:` on its XPC queue.
    private final class Receiver: NSObject, @unchecked Sendable {
        var onDevices: (([InstantHotspot]) -> Void)?

        @objc func setDelegate(_ d: Any?) {} // only for the selector

        @objc(session:updatedFoundDevices:) func session(_ s: Any?, updatedFoundDevices devices: Any?) {
            let list = (devices as? [NSObject] ?? []).compactMap { d -> InstantHotspot? in
                guard let name = d.value(forKey: "deviceName") as? String, !name.isEmpty else { return nil }
                let id = (d.value(forKey: "deviceIdentifier") as? String) ?? name
                let bars = (d.value(forKey: "signalStrength") as? NSNumber)?.intValue ?? 0
                let battery = (d.value(forKey: "batteryLife") as? NSNumber)?.intValue
                return InstantHotspot(id: id, name: name, bars: min(max(bars, 0), 4), battery: battery, device: SendableObject(object: d))
            }
            onDevices?(list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
}
