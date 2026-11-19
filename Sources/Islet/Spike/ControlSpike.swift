#if DEBUG
import AppKit
import CoreBluetooth
import CoreLocation
import CoreWLAN
import IOBluetooth

/// M10 spike: read-only probes for the Control Center page (RESEARCH.md Q16-Q21). Nothing here changes a setting.
/// Output goes to ~/Library/Logs/Islet-M10-spike.log. Removed once the questions are answered.
@MainActor
final class ControlSpike: NSObject, CLLocationManagerDelegate, CWEventDelegate {
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

    // MARK: Write probes (each change is reverted)

    func runWrites() async {
        log("# Islet M10 write probes \(Date())")
        // Dark Mode
        log("\n## Dark Mode")
        func dark() -> Bool? {
            var e: NSDictionary?
            return NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to get dark mode")?.executeAndReturnError(&e).booleanValue
        }
        func setDark(_ v: Bool) -> String {
            var e: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to \(v)")?.executeAndReturnError(&e)
            return e.map { "error \($0)" } ?? "ok"
        }
        if let before = dark() {
            log("before \(before); set \(!before): \(setDark(!before))")
            try? await Task.sleep(for: .seconds(2)); log("after: \(dark().map(String.init) ?? "?")")
            log("revert: \(setDark(before))"); try? await Task.sleep(for: .seconds(1.5)); log("final: \(dark().map(String.init) ?? "?")")
        }
        // Night Shift
        log("\n## Night Shift (CBBlueLightClient)")
        if let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
            let c = cls.init()
            typealias Get = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
            typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Bool
            func status() -> (active: UInt8, enabled: UInt8) {
                let sel = NSSelectorFromString("getBlueLightStatus:")
                let buf = UnsafeMutableRawPointer.allocate(byteCount: 128, alignment: 8); buf.initializeMemory(as: UInt8.self, repeating: 0, count: 128)
                _ = unsafeBitCast(c.method(for: sel), to: Get.self)(c, sel, buf)
                defer { buf.deallocate() }
                return (buf.load(fromByteOffset: 0, as: UInt8.self), buf.load(fromByteOffset: 1, as: UInt8.self))
            }
            func call(_ name: String, _ v: Bool) { let sel = NSSelectorFromString(name); _ = unsafeBitCast(c.method(for: sel), to: Set.self)(c, sel, v) }
            let before = status()
            log("before active=\(before.active) enabled=\(before.enabled)")
            call("setActive:", before.active == 0); try? await Task.sleep(for: .seconds(2))
            let mid = status(); log("after setActive:\(before.active == 0): active=\(mid.active) enabled=\(mid.enabled)")
            call("setActive:", before.active != 0); try? await Task.sleep(for: .seconds(2))
            let end = status(); log("reverted: active=\(end.active) enabled=\(end.enabled)")
        }
        // True Tone
        log("\n## True Tone (CBTrueToneClient)")
        if let cls = NSClassFromString("CBTrueToneClient") as? NSObject.Type {
            let c = cls.init()
            typealias Get = @convention(c) (AnyObject, Selector) -> Bool
            typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Bool
            func enabled() -> Bool { let sel = NSSelectorFromString("enabled"); return unsafeBitCast(c.method(for: sel), to: Get.self)(c, sel) }
            func set(_ v: Bool) { let sel = NSSelectorFromString("setEnabled:"); _ = unsafeBitCast(c.method(for: sel), to: Set.self)(c, sel, v) }
            let before = enabled()
            set(!before); try? await Task.sleep(for: .seconds(2)); log("before \(before); after toggle: \(enabled())")
            set(before); try? await Task.sleep(for: .seconds(2)); log("reverted: \(enabled())")
        }
        // AirDrop mode (written back to the same value)
        log("\n## AirDrop DiscoverableMode")
        let orig = shell("/usr/bin/defaults", ["read", "com.apple.sharingd", "DiscoverableMode"])
        log("original: \(orig)")
        _ = shell("/usr/bin/defaults", ["write", "com.apple.sharingd", "DiscoverableMode", "-string", "Everyone"])
        log("after write Everyone: \(shell("/usr/bin/defaults", ["read", "com.apple.sharingd", "DiscoverableMode"]))")
        _ = shell("/usr/bin/defaults", ["write", "com.apple.sharingd", "DiscoverableMode", "-string", orig])
        log("reverted: \(shell("/usr/bin/defaults", ["read", "com.apple.sharingd", "DiscoverableMode"]))")
        log("NOTE: whether sharingd honours the written value is only visible in System Settings / the AirDrop window")
        try? out.write(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-M10-writes.log"), atomically: true, encoding: .utf8)
    }

    // MARK: Active tests (disruptive; everything is put back)

    func runActive() async {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-M10-active.log")
        func flush() { try? out.write(to: file, atomically: true, encoding: .utf8) }
        log("# Islet M10 active tests \(Date())")
        guard let iface = CWWiFiClient.shared().interface() else { log("no Wi-Fi"); flush(); return }
        let original = iface.ssid()
        log("\n## Wi-Fi power  (original ssid \(original ?? "nil"))")
        do { try iface.setPower(false); log("setPower(false) ok, power=\(iface.powerOn())") } catch { log("setPower(false) FAILED: \(error)") }
        try? await Task.sleep(for: .seconds(3))
        do { try iface.setPower(true); log("setPower(true) ok") } catch { log("setPower(true) FAILED: \(error)") }
        for _ in 0..<20 where iface.ssid() == nil { try? await Task.sleep(for: .seconds(1)) }
        log("after power on: ssid=\(iface.ssid() ?? "nil")"); flush()

        log("\n## Wi-Fi join a known network (nil password)")
        let known = Set(iface.configuration()?.networkProfiles.array.compactMap { ($0 as? CWNetworkProfile)?.ssid } ?? [])
        let nets = (try? iface.scanForNetworks(withSSID: nil)) ?? []
        if let target = nets.first(where: { n in n.ssid != nil && n.ssid != iface.ssid() && known.contains(n.ssid!) }) {
            log("target: \(target.ssid ?? "?") (known, in range)")
            do { try iface.associate(to: target, password: nil); log("associate returned ok") } catch { log("associate FAILED: \(error)") }
            for _ in 0..<15 where iface.ssid() != target.ssid { try? await Task.sleep(for: .seconds(1)) }
            log("ssid now: \(iface.ssid() ?? "nil")")
            if let orig = original, let back = ((try? iface.scanForNetworks(withSSID: Data(orig.utf8))) ?? []).first {
                do { try iface.associate(to: back, password: nil); log("rejoin \(orig): ok") } catch { log("rejoin \(orig) FAILED: \(error)") }
            }
            for _ in 0..<20 where iface.ssid() != original { try? await Task.sleep(for: .seconds(1)) }
            log("final ssid: \(iface.ssid() ?? "nil")")
        } else { log("no other known network in range; skipped") }
        flush()

        log("\n## Bluetooth power (private symbols)")
        let h = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)
        typealias Get = @convention(c) () -> Int32
        typealias SetP = @convention(c) (Int32) -> Void
        if let g = h.flatMap({ dlsym($0, "IOBluetoothPreferenceGetControllerPowerState") }),
           let st = h.flatMap({ dlsym($0, "IOBluetoothPreferenceSetControllerPowerState") }) {
            let get = unsafeBitCast(g, to: Get.self), set = unsafeBitCast(st, to: SetP.self)
            log("before: \(get())")
            set(0); try? await Task.sleep(for: .seconds(3)); log("after off: \(get())")
            set(1); try? await Task.sleep(for: .seconds(4)); log("after on: \(get())")
        }
        flush()

        log("\n## Bluetooth connect / disconnect AirPods")
        let airpods = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).first { ($0.name ?? "").contains("Marco") && ($0.name ?? "").contains("AirPods") }
        if let d = airpods {
            log("device \(d.name ?? "?") connected=\(d.isConnected())")
            let r = d.openConnection(); log("openConnection -> 0x\(String(UInt32(bitPattern: r), radix: 16)); connected=\(d.isConnected())")
            try? await Task.sleep(for: .seconds(4)); log("4 s later connected=\(d.isConnected())")
            let c = d.closeConnection(); log("closeConnection -> 0x\(String(UInt32(bitPattern: c), radix: 16)); connected=\(d.isConnected())")
            try? await Task.sleep(for: .seconds(2)); log("2 s later connected=\(d.isConnected())")
        } else { log("no AirPods found") }
        log("\n# done"); flush()
        NSWorkspace.shared.open(file)
    }

    func runBluetoothConnect() async {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-M10-bt.log")
        func flush() { try? out.write(to: file, atomically: true, encoding: .utf8) }
        log("# BT connect test \(Date())")
        try? await Task.sleep(for: .seconds(2))
        let all = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        log("paired: \(all.map { ($0.name ?? "?") + "=" + String($0.isConnected()) })")
        guard let d = all.first(where: { ($0.name ?? "").contains("AirPods") && !($0.name ?? "").contains("Joystina") }) else { log("no AirPods"); flush(); return }
        if d.isConnected() { let c0 = d.closeConnection(); log("was connected; close -> 0x\(String(UInt32(bitPattern: c0), radix: 16))"); try? await Task.sleep(for: .seconds(3)); log("connected after close: \(d.isConnected())") }
        let r = d.openConnection(); log("openConnection -> 0x\(String(UInt32(bitPattern: r), radix: 16)) connected=\(d.isConnected())")
        for _ in 0..<30 where !d.isConnected() { try? await Task.sleep(for: .seconds(1)) }
        log("connected after wait: \(d.isConnected())"); flush()
        try? await Task.sleep(for: .seconds(2))
        if !d.isConnected() { log("leaving as is") } else { _ = d.closeConnection() }
        try? await Task.sleep(for: .seconds(2)); log("connected after close: \(d.isConnected())")
        log("# done"); flush()
    }

    // MARK: Event watch (Q23): Wi-Fi, Bluetooth, Focus

    private var wifiClient: CWWiFiClient?
    private var btNote: IOBluetoothUserNotification?
    private var btDisconnectNotes: [IOBluetoothUserNotification] = []
    private var focusSources: [DispatchSourceFileSystemObject] = []
    private let eventLog = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Islet-M10-events.log")
    private var lastFocus = ""

    fileprivate func event(_ s: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(s)\n"
        print(line, terminator: "")
        if let h = try? FileHandle(forWritingTo: eventLog) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: eventLog, atomically: true, encoding: .utf8) }
    }

    func watch(minutes: Double = 8) async {
        try? FileManager.default.removeItem(at: eventLog)
        event("watching for \(minutes) min. Wi-Fi: ssid now \(CWWiFiClient.shared().interface()?.ssid() ?? "nil")")
        let c = CWWiFiClient.shared(); wifiClient = c; c.delegate = self
        for t in [CWEventType.ssidDidChange, .powerDidChange, .linkDidChange] {
            do { try c.startMonitoringEvent(with: t); event("registered Wi-Fi event \(t.rawValue)") } catch { event("Wi-Fi register \(t.rawValue) failed: \(error)") }
        }
        btNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(btConnected(_:device:)))
        event("registered Bluetooth connect notification: \(btNote != nil)")
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] {
            if let n = d.register(forDisconnectNotification: self, selector: #selector(btDisconnected(_:device:))) { btDisconnectNotes.append(n) }
        }
        watchFocus()
        try? await Task.sleep(for: .seconds(minutes * 60))
        event("done")
        NSWorkspace.shared.open(eventLog)
    }

    /// IOBluetooth calls these on its own queue, not the main thread.
    @objc nonisolated private func btConnected(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "?", connected = device.isConnected()
        nonisolated(unsafe) let device = device
        Task { @MainActor in
            self.event("BT connect callback: \(name) isConnected=\(connected)")
            try? await Task.sleep(for: .seconds(1.5))
            self.event("BT 1.5 s later: \(name) isConnected=\(device.isConnected())")
            if let note = device.register(forDisconnectNotification: self, selector: #selector(self.btDisconnected(_:device:))) { self.btDisconnectNotes.append(note) }
        }
    }

    @objc nonisolated private func btDisconnected(_ n: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "?"
        Task { @MainActor in self.event("BT disconnect callback: \(name)") }
    }

    private func rawFocus() -> String {
        let f = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let d = try? Data(contentsOf: f) else { return "unreadable" }
        return String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "  ", with: "").prefix(1800).description
    }

    private func focusSummary() -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
        guard let a = try? Data(contentsOf: dir.appendingPathComponent("Assertions.json")) else { return "Assertions.json NOT readable (Full Disk Access?)" }
        var names: [String: String] = [:]
        if let m = try? Data(contentsOf: dir.appendingPathComponent("ModeConfigurations.json")),
           let j = try? JSONSerialization.jsonObject(with: m) as? [String: Any],
           let cfg = ((j["data"] as? [[String: Any]])?.first?["modeConfigurations"]) as? [String: Any] {
            for (id, v) in cfg { names[id] = (((v as? [String: Any])?["mode"]) as? [String: Any])?["name"] as? String }
        }
        guard let j = try? JSONSerialization.jsonObject(with: a) as? [String: Any],
              let records = (j["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]] else { return "parsed: no assertion records (\(a.count) bytes)" }
        let ids = records.compactMap { ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }
        return ids.isEmpty ? "no active Focus" : "active: " + ids.map { names[$0] ?? $0 }.joined(separator: ", ")
    }

    private func watchFocus() {
        event("Focus now: \(focusSummary())")
        event("Assertions raw: \(rawFocus())")
        lastFocus = focusSummary()
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB").path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { event("could not open the Focus DB folder for watching"); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = self.focusSummary()
                if now != self.lastFocus { self.event("Focus changed: \(now)"); self.lastFocus = now }
                self.event("Assertions raw: \(self.rawFocus())")
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        focusSources.append(src)
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

extension ControlSpike {
    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.event("Wi-Fi ssidDidChange \(interfaceName): now \(CWWiFiClient.shared().interface(withName: interfaceName)?.ssid() ?? "nil")") }
    }
    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.event("Wi-Fi power changed \(interfaceName): \(CWWiFiClient.shared().interface(withName: interfaceName)?.powerOn() ?? false)") }
    }
    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.event("Wi-Fi link changed \(interfaceName): ssid \(CWWiFiClient.shared().interface(withName: interfaceName)?.ssid() ?? "nil")") }
    }
}
#endif
