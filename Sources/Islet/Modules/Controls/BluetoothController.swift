import AppKit
import IOBluetooth

struct BTDevice: Identifiable, Equatable {
    var id: String          // address
    var name: String
    var connected: Bool
    var icon: String
}

/// Bluetooth: power (private IOBluetooth call), paired devices, connect/disconnect, and connect events.
/// The connect notification also fires for devices already connected at launch, for unnamed neighbours, for attempts
/// that drop, and several times per device, so an event needs: a name, still connected 1.5 s later, and a device not
/// already known to be connected. (The callbacks arrive off the main thread.)
@MainActor @Observable
final class BluetoothController: NSObject {
    private(set) var powerOn = false
    private(set) var devices: [BTDevice] = []
    private(set) var busy: Set<String> = []
    var error: String?

    @ObservationIgnored var onConnected: ((String, String) -> Void)?   // (name, icon)
    @ObservationIgnored private var connectedNow: Set<String> = []
    @ObservationIgnored private var note: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]

    // MARK: Power (private symbols, resolved at runtime)

    private typealias GetPower = @convention(c) () -> Int32
    private typealias SetPower = @convention(c) (Int32) -> Void
    private static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)
    private static let getPower = handle.flatMap { dlsym($0, "IOBluetoothPreferenceGetControllerPowerState") }.map { unsafeBitCast($0, to: GetPower.self) }
    private static let setPower = handle.flatMap { dlsym($0, "IOBluetoothPreferenceSetControllerPowerState") }.map { unsafeBitCast($0, to: SetPower.self) }

    var powerAvailable: Bool { Self.getPower != nil && Self.setPower != nil }

    func start() {
        refresh()
        connectedNow = Set(devices.filter(\.connected).map(\.id))
        note = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connectCallback(_:device:)))
    }

    func refresh() {
        powerOn = (Self.getPower?() ?? 1) != 0
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        devices = paired.compactMap { d in
            guard let address = d.addressString, let name = d.name, !name.isEmpty else { return nil }
            registerDisconnect(d, address: address)
            guard Self.isAccessory(name: name, major: d.deviceClassMajor) else { return nil }
            return BTDevice(id: address, name: name, connected: d.isConnected(), icon: Self.icon(name: name, major: d.deviceClassMajor))
        }.sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
    }

    func setPower(_ on: Bool) {
        Self.setPower?(on ? 1 : 0)
        powerOn = on
        Task { try? await Task.sleep(for: .seconds(2)); self.refresh() }
    }

    // MARK: Connect and disconnect

    func toggle(_ device: BTDevice) async {
        busy.insert(device.id); error = nil
        defer { busy.remove(device.id) }
        let address = device.id, connect = !device.connected
        let ok: Bool = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let d = IOBluetoothDevice(addressString: address) else { cont.resume(returning: false); return }
                if connect {
                    _ = d.openConnection()
                    for _ in 0..<40 where !d.isConnected() { Thread.sleep(forTimeInterval: 0.5) }
                    cont.resume(returning: d.isConnected())
                } else {
                    _ = d.closeConnection()
                    cont.resume(returning: !d.isConnected())
                }
            }
        }
        if !ok { error = connect ? "Couldn't connect \(device.name). Is it nearby and awake?" : "Couldn't disconnect \(device.name)." }
        refresh()
    }

    // MARK: Notifications

    private func registerDisconnect(_ d: IOBluetoothDevice, address: String) {
        guard disconnectNotes[address] == nil else { return }
        disconnectNotes[address] = d.register(forDisconnectNotification: self, selector: #selector(disconnectCallback(_:device:)))
    }

    @objc nonisolated private func connectCallback(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        let name = device.name ?? "", major = device.deviceClassMajor
        Task { @MainActor in await self.connected(address: address, name: name, major: major) }
    }

    @objc nonisolated private func disconnectCallback(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        Task { @MainActor in self.connectedNow.remove(address); self.refresh() }
    }

    private func connected(address: String, name: String, major: UInt32) async {
        guard !name.isEmpty, Self.isAccessory(name: name, major: major), !connectedNow.contains(address) else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard !connectedNow.contains(address), IOBluetoothDevice(addressString: address)?.isConnected() == true else { return }
        connectedNow.insert(address)
        refresh()
        onConnected?(name, Self.icon(name: name, major: major))
    }

    /// Devices one connects to a Mac on purpose: headphones, speakers, mice, keyboards, controllers. Phones, tablets,
    /// watches and computers are paired for other reasons and are left out. Most Bluetooth LE accessories report
    /// class 0, so the name decides too.
    static func isAccessory(name: String, major: UInt32) -> Bool {
        let n = name.lowercased()
        for no in ["iphone", "ipad", "watch", "macbook", "imac", "mac mini", "mac studio", "mac pro", "apple tv", "iphone duo"] where n.contains(no) { return false }
        if major == 4 || major == 5 { return true }
        for yes in ["airpods", "beats", "headphone", "headset", "earbud", "buds", "speaker", "soundbar", "keyboard", "mouse", "trackpad",
                    "controller", "gamepad", "dualsense", "dualshock", "xbox", "bose", "sony", "jbl", "wh-", "wf-", "pods", "boom"] where n.contains(yes) { return true }
        return false
    }

    static func icon(name: String, major: UInt32) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods") { return "airpodspro" }
        if n.contains("watch") { return "applewatch" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("iphone") { return "iphone" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("mouse") || n.contains("trackpad") { return "magicmouse" }
        if n.contains("homepod") || n.contains("speaker") || n.contains("soundbar") || n.contains("boom") || n.contains("jbl") { return "hifispeaker.fill" }
        if n.contains("controller") || n.contains("gamepad") || n.contains("dualsense") || n.contains("dualshock") || n.contains("xbox") { return "gamecontroller.fill" }
        if n.contains("headphone") || n.contains("headset") || n.contains("beats") || n.contains("bose") || n.contains("sony") || n.contains("wh-") { return "headphones" }
        switch major {
        case 1: return "laptopcomputer"
        case 2: return "iphone"
        case 4: return "headphones"
        case 5: return "keyboard"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
