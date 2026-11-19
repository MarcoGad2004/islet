#if DEBUG
import AppKit
import CoreBluetooth
import CoreLocation
import CoreWLAN
import IOBluetooth

/// M10 spike: read-only probes for the Control Center page (RESEARCH.md Q16-Q21). Nothing here changes a setting.
/// Output goes to ~/Library/Logs/Islet-M10-spike.log. Removed once the questions are answered.
@MainActor
final class ControlSpike: NSObject, CLLocationManagerDelegate {
    private let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-M10-spike.log")
    private var location: CLLocationManager?
    private var out = ""

    private func log(_ s: String) { out += s + "\n"; print(s) }

    func run() async {
        log("# Islet M10 spike \(Date())  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        await wifi()
        bluetooth()
        focus()
        airdrop()
        displays()
        displayToggles()
        await darkModeScript()
        try? out.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }

    // MARK: Q16 Wi-Fi

    private func wifi() async {
        log("\n## Q16 Wi-Fi")
        let lm = CLLocationManager(); location = lm; lm.delegate = self
        log("location status before: \(lm.authorizationStatus.rawValue) (0 notDetermined, 3 always, 4 whenInUse)")
        if lm.authorizationStatus == .notDetermined {
            lm.requestWhenInUseAuthorization()
            for _ in 0..<40 where lm.authorizationStatus == .notDetermined { try? await Task.sleep(for: .milliseconds(500)) }
        }
        log("location status now: \(lm.authorizationStatus.rawValue)")
        guard let iface = CWWiFiClient.shared().interface() else { log("no Wi-Fi interface"); return }
        log("interface \(iface.interfaceName ?? "?") power=\(iface.powerOn()) ssid=\(iface.ssid() ?? "nil") rssi=\(iface.rssiValue())")
        do {
            let nets = try iface.scanForNetworks(withSSID: nil)
            let named = nets.filter { $0.ssid != nil }
            log("scan: \(nets.count) networks, \(named.count) with names; secured=\(nets.filter { !$0.supportsSecurity(.none) }.count)")
            log("sample: " + named.prefix(5).map { "\($0.ssid ?? "?") \($0.rssiValue)dBm" }.joined(separator: ", "))
        } catch { log("scan failed: \(error)") }
        let known = iface.configuration()?.networkProfiles.array.compactMap { ($0 as? CWNetworkProfile)?.ssid } ?? []
        log("known networks readable: \(known.count) \(known.prefix(3))")
        log("setPower not exercised (would drop the connection)")
    }

    // MARK: Q17 Bluetooth

    private func bluetooth() {
        log("\n## Q17 Bluetooth")
        log("CBManager authorization: \(CBCentralManager.authorization.rawValue) (3 allowedAlways)")
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        log("paired devices: \(devices.count)")
        for d in devices { log("  \(d.name ?? "?")  connected=\(d.isConnected())  addr=\(d.addressString ?? "?")") }
        let h = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)
        for sym in ["IOBluetoothPreferenceGetControllerPowerState", "IOBluetoothPreferenceSetControllerPowerState"] {
            log("private symbol \(sym): \(h.flatMap { dlsym($0, sym) } != nil ? "present" : "missing")")
        }
        typealias Get = @convention(c) () -> Int32
        if let g = h.flatMap({ dlsym($0, "IOBluetoothPreferenceGetControllerPowerState") }) {
            log("controller power state (read): \(unsafeBitCast(g, to: Get.self)())")
        }
    }

    // MARK: Q18 Focus

    private func focus() {
        log("\n## Q18 Focus")
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
        for name in ["Assertions.json", "ModeConfigurations.json"] {
            let f = dir.appendingPathComponent(name)
            do {
                let d = try Data(contentsOf: f)
                log("\(name): readable, \(d.count) bytes")
                if name == "ModeConfigurations.json", let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let data = (j["data"] as? [[String: Any]])?.first, let cfgs = data["modeConfigurations"] as? [String: Any] {
                    let names = cfgs.values.compactMap { (($0 as? [String: Any])?["mode"] as? [String: Any])?["name"] as? String }
                    log("  modes: \(names)")
                }
                if name == "Assertions.json" { log("  \(String(data: d.prefix(300), encoding: .utf8) ?? "")") }
            } catch { log("\(name): NOT readable (\((error as NSError).code)) \(error.localizedDescription)") }
        }
        log("shortcuts list: " + shell("/usr/bin/shortcuts", ["list"]).replacingOccurrences(of: "\n", with: " | "))
    }

    // MARK: Q19 AirDrop

    private func airdrop() {
        log("\n## Q19 AirDrop")
        log("defaults com.apple.sharingd DiscoverableMode: " + shell("/usr/bin/defaults", ["read", "com.apple.sharingd", "DiscoverableMode"]))
        log("AirDrop window via NSWorkspace: openable = \(NSWorkspace.shared.urlForApplication(toOpen: URL(string: "airdrop://")!) != nil)")
    }

    // MARK: Q20 Mirroring

    private func displays() {
        log("\n## Q20 Mirroring")
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        for id in ids.prefix(Int(n)) {
            log("display \(id): builtin=\(CGDisplayIsBuiltin(id) != 0) mirrored=\(CGDisplayIsInMirrorSet(id) != 0) \(CGDisplayPixelsWide(id))x\(CGDisplayPixelsHigh(id))")
        }
        log("AirPlay target list: no public API; CGConfigureDisplayMirrorOfDisplay covers wired/Sidecar only")
    }

    // MARK: Q21 Display toggles

    private func displayToggles() {
        log("\n## Q21 Display toggles")
        log("AppleInterfaceStyle default: \(UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light")")
        let h = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        log("CoreBrightness loaded: \(h != nil)")
        for name in ["CBBlueLightClient", "CBTrueToneClient", "KeyboardBrightnessClient"] {
            log("class \(name): \(NSClassFromString(name) != nil ? "present" : "missing")")
        }
        if let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
            let c = cls.init()
            let sel = NSSelectorFromString("getBlueLightStatus:")
            if c.responds(to: sel) {
                typealias F = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
                let imp = unsafeBitCast(c.method(for: sel), to: F.self)
                let buf = UnsafeMutableRawPointer.allocate(byteCount: 128, alignment: 8); buf.initializeMemory(as: UInt8.self, repeating: 0, count: 128)
                let ok = imp(c, sel, buf)
                log("Night Shift status call ok=\(ok) active=\(buf.load(fromByteOffset: 0, as: UInt8.self)) enabled=\(buf.load(fromByteOffset: 1, as: UInt8.self))")
                buf.deallocate()
            } else { log("CBBlueLightClient has no getBlueLightStatus:") }
            log("Night Shift setters: setEnabled:=\(c.responds(to: NSSelectorFromString("setEnabled:"))) setActive:=\(c.responds(to: NSSelectorFromString("setActive:")))")
        }
        if let cls = NSClassFromString("CBTrueToneClient") as? NSObject.Type {
            let c = cls.init()
            typealias B = @convention(c) (AnyObject, Selector) -> Bool
            for s in ["supported", "available", "enabled"] {
                let sel = NSSelectorFromString(s)
                if c.responds(to: sel) { log("True Tone \(s) = \(unsafeBitCast(c.method(for: sel), to: B.self)(c, sel))") } else { log("True Tone: no \(s)") }
            }
            log("True Tone setEnabled: = \(c.responds(to: NSSelectorFromString("setEnabled:")))")
        }
    }

    private func darkModeScript() async {
        log("\n## Dark Mode via System Events (read)")
        var err: NSDictionary?
        let r = NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to get dark mode")?.executeAndReturnError(&err)
        log(r.map { "dark mode = \($0.booleanValue)" } ?? "failed: \(err ?? [:])")
    }

    // MARK: helpers

    private func shell(_ path: String, _ args: [String]) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return "failed to run: \(error)" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
