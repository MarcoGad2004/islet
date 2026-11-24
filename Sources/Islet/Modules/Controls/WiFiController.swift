import AppKit
import CoreLocation
import CoreWLAN
import Network

struct WiFiNetwork: Identifiable, Equatable {
    var ssid: String
    var rssi: Int
    var secured: Bool
    var known: Bool
    /// WPA/WPA2/WPA3 Enterprise (802.1X): joined with a username and password.
    var enterprise = false
    /// A phone's Personal Hotspot: one this Mac has seen as a hotspot before, or named like one.
    var hotspot = false
    var id: String { ssid }
    /// 1...3 bars.
    var bars: Int { rssi > -60 ? 3 : (rssi > -72 ? 2 : 1) }
}

/// Wi-Fi: power, the connected network, nearby networks and joining (CoreWLAN). Network names need Location
/// Services. Events fire when the connected network changes (debounced, never for nil), saying whether it is a phone's
/// Personal Hotspot.
@MainActor @Observable
final class WiFiController: NSObject, CWEventDelegate, CLLocationManagerDelegate {
    private(set) var powerOn = false
    private(set) var ssid: String?
    /// The connected network is a phone's Personal Hotspot (macOS marks the link expensive, or the address is in the
    /// iPhone hotspot range).
    private(set) var hotspot = false
    private(set) var networks: [WiFiNetwork] = []
    private(set) var scanning = false
    private(set) var joining: String?
    /// Phones nearby offering Instant Hotspot (found over Bluetooth while the Wi-Fi panel is open).
    private(set) var instantHotspots: [InstantHotspot] = []
    @ObservationIgnored private let hotspotBrowser = InstantHotspotBrowser()
    @ObservationIgnored private var browseStop: Task<Void, Never>?
    private(set) var locationStatus = CLAuthorizationStatus.notDetermined
    var error: String?

    @ObservationIgnored var onConnected: ((_ ssid: String, _ hotspot: Bool) -> Void)?
    /// A join started from the panel, step by step, for the notch to show once the panel closes.
    @ObservationIgnored var onProgress: ((ConnectionProgress) -> Void)?
    @ObservationIgnored private let path = NWPathMonitor(requiredInterfaceType: .wifi)
    /// The network macOS marked expensive (metered), taken when the path changed. Tied to a name so a stale flag from
    /// the last network (a hotspot) doesn't stick to the next one.
    @ObservationIgnored private var expensiveSSID: String?
    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private var lastAnnounced: String?
    /// The network the user just picked in the panel: joining it isn't news, so no notice.
    @ObservationIgnored private var requested: String?
    /// v2: the first version could record an ordinary network right after leaving a hotspot.
    private static let hotspotsKey = "wifiKnownHotspots2"
    /// Networks seen as a Personal Hotspot while connected, so the list can mark them when they're only in range.
    @ObservationIgnored private var knownHotspots = Set(UserDefaults.standard.stringArray(forKey: hotspotsKey) ?? [])
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    var locationAllowed: Bool { locationStatus == .authorizedAlways || locationStatus == .authorized }
    /// On a network whose name macOS won't tell without Location access: the Wi-Fi interface has an address but no
    /// network name. Shown as "Location needed", not "Not connected".
    private(set) var nameHidden = false

    /// For the tile and quick info: the network, "Location needed", "Not connected", or nil when Wi-Fi is off.
    var shortStatus: String? {
        guard powerOn else { return nil }
        return ssid ?? (nameHidden ? "Location needed" : "Not connected")
    }
    /// Joined to a network, named or not.
    var isConnected: Bool { powerOn && (ssid != nil || nameHidden) }

    func start() {
        location.delegate = self
        locationStatus = location.authorizationStatus
        refresh()
        lastAnnounced = ssid
        let client = CWWiFiClient.shared()
        client.delegate = self
        for t in [CWEventType.ssidDidChange, .powerDidChange, .linkDidChange] { try? client.startMonitoringEvent(with: t) }
        path.pathUpdateHandler = { [weak self] p in
            let expensive = p.status == .satisfied && p.isExpensive
            Task { @MainActor in
                self?.expensiveSSID = expensive ? CWWiFiClient.shared().interface()?.ssid() : nil
                self?.refresh()
            }
        }
        path.start(queue: .global(qos: .utility))
    }

    func refresh() {
        locationStatus = location.authorizationStatus
        let i = CWWiFiClient.shared().interface()
        powerOn = i?.powerOn() ?? false
        ssid = powerOn ? i?.ssid() : nil
        let address = i?.interfaceName.flatMap(Self.ipv4)
        nameHidden = powerOn && ssid == nil && !locationAllowed && address != nil
        let phoneAddress = address.map(Self.isPhoneHotspotAddress) == true
        let phone = ssid.map { s in instantHotspots.contains { $0.name == s } } ?? false
        hotspot = ssid != nil && (phoneAddress || phone || expensiveSSID == ssid)
        // Remembered only on firm evidence (an iPhone hotspot address, or a phone offering Instant Hotspot), never
        // on the metered flag alone.
        if let ssid, phoneAddress || phone, !knownHotspots.contains(ssid) {
            knownHotspots.insert(ssid)
            UserDefaults.standard.set(Array(knownHotspots), forKey: Self.hotspotsKey)
        }
    }

    /// Default names of phone hotspots ("Marco's iPhone", "AndroidAP...").
    nonisolated static func looksLikeHotspot(_ ssid: String) -> Bool {
        ["iphone", "ipad", "androidap", "android ap"].contains { ssid.lowercased().contains($0) }
    }

    /// iPhone and iPad Personal Hotspots hand out 172.20.10.2-14.
    nonisolated static func isPhoneHotspotAddress(_ a: String) -> Bool { a.hasPrefix("172.20.10.") }

    /// The interface's IPv4 address, once DHCP has given it one.
    nonisolated static func ipv4(_ interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard String(cString: ifa.ifa_name) == interface, let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return nil
    }

    /// Starts looking for Instant Hotspot phones, for a minute (the panel calls this each time it shows Wi-Fi).
    func browseHotspots() {
        hotspotBrowser.onChange = { [weak self] list in self?.instantHotspots = list }
        hotspotBrowser.start()
        browseStop?.cancel()
        browseStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.stopBrowsingHotspots()
        }
    }

    func stopBrowsingHotspots() {
        browseStop?.cancel(); browseStop = nil
        hotspotBrowser.stop()
    }

    /// Asks the phone to turn on its hotspot, then joins it with the name and password it hands back.
    func join(_ h: InstantHotspot) async {
        guard joining == nil else { return }
        error = nil; joining = h.name; requested = h.name
        defer { joining = nil }
        report(h.name, hotspot: true, .working("Asking \(h.name)…"))
        switch await hotspotBrowser.enable(h) {
        case .failed(let message):
            finish(h.name, hotspot: true, message: message)
        case .on(let ssid, let password):
            let target = ssid ?? h.name
            requested = target
            report(h.name, hotspot: true, .working("Joining \(h.name)…"))
            // The phone takes a few seconds to start broadcasting, so keep looking for it.
            var message = await associate(ssid: target, password: password, enterprise: false, username: nil, attempts: 8)
            if message == nil, !(await connected(to: target)) { message = "\(h.name) didn't connect. Try again." }
            finish(h.name, hotspot: true, message: message)
        }
    }

    /// Waits up to 15 s for the Mac to be on `ssid`.
    private func connected(to ssid: String) async -> Bool {
        for _ in 0..<15 {
            refresh()
            if self.ssid == ssid { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    private func report(_ name: String, hotspot: Bool, _ state: ConnectionProgress.State) {
        onProgress?(ConnectionProgress(name: name, hotspot: hotspot, state: state))
    }

    private func finish(_ name: String, hotspot: Bool, message: String?) {
        if message != nil { requested = nil }
        error = message
        report(name, hotspot: hotspot, message.map { .failed($0) } ?? .done)
    }

    /// Finds `ssid` and associates, off the main thread. Returns an error message, or nil. Retries a missing or
    /// failing network `attempts` times (a hotspot that is still starting up).
    private func associate(ssid: String, password: String?, enterprise: Bool, username: String?, attempts: Int) async -> String? {
        let ssidData = Data(ssid.utf8)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var last = "\(ssid) isn't in range."
                for attempt in 0..<attempts {
                    if attempt > 0 { Thread.sleep(forTimeInterval: 1.5) }
                    guard let iface = CWWiFiClient.shared().interface(),
                          let target = ((try? iface.scanForNetworks(withSSID: ssidData)) ?? []).first else { continue }
                    do {
                        if enterprise {
                            try iface.associate(toEnterpriseNetwork: target, identity: nil, username: username, password: password)
                        } else {
                            try iface.associate(to: target, password: password)
                        }
                        cont.resume(returning: nil); return
                    } catch {
                        if password == nil { last = enterprise ? "Sign in to join." : "This network needs a password." }
                        else if enterprise { last = "Couldn't sign in. Check the username and password, or use Wi-Fi Settings." }
                        else { last = "Couldn't join. Check the password." }
                    }
                }
                cont.resume(returning: last)
            }
        }
    }

    /// Leaves the current network. macOS may join another saved one on its own afterwards.
    func disconnect() async {
        guard let current = ssid else { return }
        joining = current; error = nil
        defer { joining = nil }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                CWWiFiClient.shared().interface()?.disassociate()
                cont.resume()
            }
        }
        try? await Task.sleep(for: .milliseconds(500))
        refresh()
        await scan()
    }

    func requestLocation() { location.requestWhenInUseAuthorization() }

    func setPower(_ on: Bool) {
        do { try CWWiFiClient.shared().interface()?.setPower(on) } catch { self.error = "Couldn't change Wi-Fi: \(error.localizedDescription)" }
        refresh()
    }

    /// Scans for nearby networks (about two seconds). Asks for Location access the first time.
    func scan() async {
        refresh()
        guard powerOn else { networks = []; return }
        if locationStatus == .notDetermined { requestLocation(); return }
        guard locationAllowed else { return }
        scanning = true; defer { scanning = false }
        let current = ssid
        // A full scan takes several seconds; show what macOS already knows straight away.
        if networks.isEmpty, let iface = CWWiFiClient.shared().interface() {
            let known = Set(iface.configuration()?.networkProfiles.array.compactMap { ($0 as? CWNetworkProfile)?.ssid } ?? [])
            networks = Self.convert(Array(iface.cachedScanResults() ?? []), known: known, hotspots: knownHotspots, current: current)
        }
        let hotspots = knownHotspots
        let result: [WiFiNetwork] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let iface = CWWiFiClient.shared().interface()
                let known = Set(iface?.configuration()?.networkProfiles.array.compactMap { ($0 as? CWNetworkProfile)?.ssid } ?? [])
                let found = (try? iface?.scanForNetworks(withSSID: nil)) ?? []
                cont.resume(returning: Self.convert(Array(found), known: known, hotspots: hotspots, current: current))
            }
        }
        networks = result
    }

    nonisolated static func convert(_ found: [CWNetwork], known: Set<String>, hotspots: Set<String>, current: String?) -> [WiFiNetwork] {
        var best: [String: WiFiNetwork] = [:]
        for n in found {
            guard let s = n.ssid, !s.isEmpty else { continue }
            let enterprise = [CWSecurity.enterprise, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .wpa3Enterprise,
                              .dynamicWEP].contains { n.supportsSecurity($0) }
                && ![CWSecurity.personal, .wpaPersonal, .wpaPersonalMixed, .wpa2Personal, .wpa3Personal, .wpa3Transition]
                    .contains { n.supportsSecurity($0) }
            let item = WiFiNetwork(ssid: s, rssi: n.rssiValue, secured: !n.supportsSecurity(.none), known: known.contains(s),
                                   enterprise: enterprise, hotspot: hotspots.contains(s) || looksLikeHotspot(s))
            if let old = best[s], old.rssi >= item.rssi { continue }
            best[s] = item
        }
        return best.values.sorted { ($0.ssid == current ? 0 : 1, -$0.rssi) < ($1.ssid == current ? 0 : 1, -$1.rssi) }
    }

    /// Joins a network. Returns an error message, or nil. Secured networks need the password, Enterprise ones the
    /// username too. A saved network can be tried with neither: macOS uses what it has stored.
    func join(_ network: WiFiNetwork, username: String? = nil, password: String?) async -> String? {
        joining = network.ssid; error = nil; requested = network.ssid
        defer { joining = nil }
        report(network.ssid, hotspot: network.hotspot, .working("Joining \(network.ssid)…"))
        var message = await associate(ssid: network.ssid, password: password, enterprise: network.enterprise,
                                      username: username, attempts: 1)
        if message == nil, !(await connected(to: network.ssid)) { message = "\(network.ssid) didn't connect. Try again." }
        finish(network.ssid, hotspot: network.hotspot, message: message)
        return message
    }

    // MARK: Events (delivered off the main thread)

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) { Task { @MainActor in self.changed() } }
    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) { Task { @MainActor in self.changed() } }
    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { Task { @MainActor in self.changed() } }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationStatus = status
            self.refresh() // the name shows (or hides) straight away
            if self.locationAllowed { await self.scan() }
        }
    }

    private func changed() {
        refresh()
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.refresh()
            guard let now = self.ssid, now != self.lastAnnounced else { return }
            // Wait (a few seconds at most) for an address, which is what tells a Personal Hotspot apart.
            for _ in 0..<8 {
                if let name = CWWiFiClient.shared().interface()?.interfaceName, Self.ipv4(name) != nil { break }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
            }
            self.refresh()
            guard self.ssid == now else { return }
            self.lastAnnounced = now
            if self.requested == now { self.requested = nil; return }
            self.onConnected?(now, self.hotspot)
        }
    }
}
