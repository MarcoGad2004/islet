import Foundation

/// A phone offering its Personal Hotspot through Instant Hotspot. These come from sharingd over Bluetooth, not from a
/// Wi-Fi scan (the phone only starts broadcasting once asked), which is why CoreWLAN never lists them.
struct InstantHotspot: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// 0...4 bars of cellular signal.
    var bars: Int
    /// Battery in 25% steps, rounded up (sharingd only gets this much from the phone): 75 means 51-75%.
    var battery: Int?
    /// "5G", "LTE" and so on: the cellular network, as sharingd names it; nil when it doesn't say.
    var network: String?
    fileprivate var device: SendableObject

    static func == (a: InstantHotspot, b: InstantHotspot) -> Bool {
        a.id == b.id && a.name == b.name && a.bars == b.bars && a.battery == b.battery && a.network == b.network
    }

    /// The network's name from the device's description ("…, network type: 5G, …"). `networkType` itself is a bare
    /// code (8 for 5G) with no public mapping, and the description is where sharingd turns it into words.
    static func networkName(_ description: String) -> String? {
        guard let r = description.range(of: "network type: ") else { return nil }
        let name = description[r.upperBound...].prefix { $0 != "," && $0 != ">" }.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 8, !["none", "unknown", "(null)", "invalid"].contains(name.lowercased()),
              !name.allSatisfy(\.isNumber) else { return nil }
        return name
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

    enum EnableResult: Sendable {
        /// The phone's hotspot is on: its network name and password, for joining it (macOS doesn't join by itself).
        case on(ssid: String?, password: String?)
        case failed(String)
    }

    /// Asks the phone to turn on its hotspot. sharingd answers with the network's name and password (or an error);
    /// the caller joins the network with them, as Control Center does.
    func enable(_ h: InstantHotspot) async -> EnableResult {
        let sel = NSSelectorFromString("enableHotspotForDevice:withCompletionHandler:")
        guard let s = session, s.responds(to: sel) else { return .failed("Couldn't reach \(h.name).") }
        // The protocol's handler is (SFRemoteHotspotInfo, NSError), but SFRemoteHotspotSession's own wrapper unpacks
        // the info and calls ours with (name, password, error): three values (read from its disassembly on macOS
        // 27.2). Each is checked before use, so a different shape fails cleanly instead of crashing.
        typealias Handler = @convention(block) (AnyObject?, AnyObject?, AnyObject?) -> Void
        typealias Enable = @convention(c) (NSObject, Selector, NSObject, @escaping Handler) -> Void
        let imp = unsafeBitCast(s.method(for: sel), to: Enable.self)
        let device = h.device.object, name = h.name
        return await withCheckedContinuation { cont in
            let once = Once(cont)
            imp(s, sel, device) { ssid, password, error in
                if let error = error as? NSError {
                    NSLog("Islet: hotspot enable failed: %@", error.localizedDescription)
                    once.resume(.failed("\(name) couldn't turn on its hotspot."))
                } else {
                    once.resume(.on(ssid: ssid as? String, password: password as? String))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { once.resume(.failed("\(name) didn't answer. Unlock it and try again.")) }
        }
    }

    /// Resumes a continuation exactly once (the answer and the time limit race).
    private final class Once: @unchecked Sendable {
        private var cont: CheckedContinuation<EnableResult, Never>?
        private let lock = NSLock()
        init(_ c: CheckedContinuation<EnableResult, Never>) { cont = c }
        func resume(_ r: EnableResult) {
            lock.lock(); let c = cont; cont = nil; lock.unlock()
            c?.resume(returning: r)
        }
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
                return InstantHotspot(id: id, name: name, bars: min(max(bars, 0), 4), battery: battery,
                                      network: InstantHotspot.networkName(d.description), device: SendableObject(object: d))
            }
            onDevices?(list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
}
