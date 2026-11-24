import AppKit
import CoreBluetooth
import IOBluetooth

struct BTDevice: Identifiable, Equatable {
    var id: String          // address
    var name: String
    var connected: Bool
    var icon: String
    var battery: BTBattery? = nil
}

/// A connected device's charge, in percent, as macOS reports it: earbuds each and their case, or one battery.
struct BTBattery: Equatable, Sendable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var single: Int?

    /// The earbuds' charge (the lower of the two, as the one that runs out first), else the single battery.
    var main: Int? {
        switch (left, right) {
        case let (l?, r?): min(l, r)
        case let (l?, nil): l
        case let (nil, r?): r
        default: single
        }
    }
    var hasEarbuds: Bool { left != nil || right != nil }
}

/// Bluetooth: power (private IOBluetooth call), paired devices, and connect/disconnect. Connect and disconnect
/// notifications keep the device list current; a device connecting shows no event in the notch, as macOS shows its own
/// card (owner, 2026-11-24). (The callbacks arrive off the main thread.)
@MainActor @Observable
final class BluetoothController: NSObject {
    private(set) var powerOn = false
    private(set) var devices: [BTDevice] = []
    private(set) var busy: Set<String> = []
    var error: String?

    @ObservationIgnored private var note: IOBluetoothUserNotification?
    /// Names and charge from System Information, by address (see `readDetails`).
    @ObservationIgnored private var details: [String: Details] = [:]
    @ObservationIgnored private var detailsRead = Date.distantPast
    @ObservationIgnored private var readingDetails = false
    @ObservationIgnored private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]

    // MARK: Power (private symbols, resolved at runtime)

    private typealias GetPower = @convention(c) () -> Int32
    private typealias SetPower = @convention(c) (Int32) -> Void
    nonisolated(unsafe) private static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)
    nonisolated(unsafe) private static let getPower = handle.flatMap { dlsym($0, "IOBluetoothPreferenceGetControllerPowerState") }.map { unsafeBitCast($0, to: GetPower.self) }
    private static let setPower = handle.flatMap { dlsym($0, "IOBluetoothPreferenceSetControllerPowerState") }.map { unsafeBitCast($0, to: SetPower.self) }

    var powerAvailable: Bool { Self.getPower != nil && Self.setPower != nil }

    @ObservationIgnored private var waiting = false

    func start() {
        // Until Bluetooth access is decided, the first IOBluetooth call waits on the permission prompt; on the main
        // thread that froze the whole app at launch until the prompt was answered. Ask from a background thread
        // instead and start once there's an answer.
        guard CBManager.authorization == .allowedAlways else {
            guard CBManager.authorization == .notDetermined, !waiting else { return }
            waiting = true
            Task.detached(priority: .utility) {
                _ = Self.getPower?()
                await MainActor.run { [weak self] in
                    self?.waiting = false
                    if CBManager.authorization == .allowedAlways { self?.start() }
                }
            }
            return
        }
        refresh()
        note = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connectCallback(_:device:)))
    }

    func refresh() {
        guard CBManager.authorization == .allowedAlways else { return }
        powerOn = (Self.getPower?() ?? 1) != 0
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        devices = paired.compactMap { d in
            guard let address = d.addressString, let name = d.name, !name.isEmpty else { return nil }
            registerDisconnect(d, address: address)
            guard Self.isAccessory(name: name, major: d.deviceClassMajor) else { return nil }
            let connected = d.isConnected()
            let info = details[Self.key(address)]
            return BTDevice(id: address, name: info?.name ?? name, connected: connected,
                            icon: Self.icon(name: name, major: d.deviceClassMajor), battery: connected ? info?.battery : nil)
        }.sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
        updateDetails()
    }

    // MARK: Names and charge

    struct Details: Sendable {
        var name: String
        var battery: BTBattery?
    }

    /// IOBluetooth often knows a device only by its model ("AirPods Pro") and never its charge. System Information has
    /// the name you gave it ("Marco's AirPods Pro") and, for AirPods and many others, each earbud's and the case's
    /// charge. It's read in the background (about 60 ms) at most every 10 s, whenever the list refreshes (quick info
    /// showing, the panel opening, a device connecting), and the list is rebuilt with it.
    private func updateDetails() {
        guard !readingDetails, Date().timeIntervalSince(detailsRead) > 10, devices.contains(where: \.connected) || details.isEmpty
        else { return }
        readingDetails = true
        Task.detached(priority: .utility) {
            let read = Self.readDetails()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.readingDetails = false
                self.detailsRead = Date()
                guard let read else { return }
                self.details = read
                self.applyDetails()
            }
        }
    }

    /// Puts the names and charge on the current list without asking IOBluetooth again.
    private func applyDetails() {
        devices = devices.map { d in
            var d = d
            if let info = details[Self.key(d.id)] {
                d.name = info.name
                d.battery = d.connected ? info.battery : nil
            }
            return d
        }.sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
    }

    /// "38-C4-3A-16-FF-CD" and "38:c4:3a:16:ff:cd" alike.
    nonisolated private static func key(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":")
    }

    /// `system_profiler SPBluetoothDataType -json`: devices under "device_connected" and "device_not_connected", each a
    /// one-key dictionary of name to details ("device_address", "device_batteryLevelLeft": "81%", …). Nil if it fails.
    nonisolated private static func readDetails() -> [String: Details]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parseDetails(data)
    }

    nonisolated static func parseDetails(_ data: Data) -> [String: Details]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        func percent(_ v: Any?) -> Int? {
            (v as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        }
        var result: [String: Details] = [:]
        for section in sections {
            for list in ["device_connected", "device_not_connected"] {
                for entry in section[list] as? [[String: Any]] ?? [] {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any], let address = info["device_address"] as? String else { continue }
                        let b = BTBattery(left: percent(info["device_batteryLevelLeft"]), right: percent(info["device_batteryLevelRight"]),
                                          caseLevel: percent(info["device_batteryLevelCase"]),
                                          single: percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryLevel"]))
                        let known = b.left != nil || b.right != nil || b.caseLevel != nil || b.single != nil
                        result[key(address)] = Details(name: name, battery: known ? b : nil)
                    }
                }
            }
        }
        return result
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
        // The connection settles a moment after the notification (and it fires several times per device).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            self.refresh()
        }
    }

    @objc nonisolated private func disconnectCallback(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor in self.refresh() }
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
