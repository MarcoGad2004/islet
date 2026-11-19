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
    private(set) var locationStatus = CLAuthorizationStatus.notDetermined
    var error: String?

    @ObservationIgnored var onConnected: ((_ ssid: String, _ hotspot: Bool) -> Void)?
    @ObservationIgnored private let path = NWPathMonitor(requiredInterfaceType: .wifi)
    @ObservationIgnored private var pathExpensive = false
    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private var lastAnnounced: String?
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    var locationAllowed: Bool { locationStatus == .authorizedAlways || locationStatus == .authorized }

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
            Task { @MainActor in self?.pathExpensive = expensive; self?.refresh() }
        }
        path.start(queue: .global(qos: .utility))
    }

    func refresh() {
        locationStatus = location.authorizationStatus
        let i = CWWiFiClient.shared().interface()
        powerOn = i?.powerOn() ?? false
        ssid = powerOn ? i?.ssid() : nil
        let address = i?.interfaceName.flatMap(Self.ipv4)
        hotspot = ssid != nil && (pathExpensive || address.map(Self.isPhoneHotspotAddress) == true)
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
            networks = Self.convert(Array(iface.cachedScanResults() ?? []), known: known, current: current)
        }
        let result: [WiFiNetwork] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let iface = CWWiFiClient.shared().interface()
                let known = Set(iface?.configuration()?.networkProfiles.array.compactMap { ($0 as? CWNetworkProfile)?.ssid } ?? [])
                let found = (try? iface?.scanForNetworks(withSSID: nil)) ?? []
                cont.resume(returning: Self.convert(Array(found), known: known, current: current))
            }
        }
        networks = result
    }

    nonisolated static func convert(_ found: [CWNetwork], known: Set<String>, current: String?) -> [WiFiNetwork] {
        var best: [String: WiFiNetwork] = [:]
        for n in found {
            guard let s = n.ssid, !s.isEmpty else { continue }
            let enterprise = [CWSecurity.enterprise, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .wpa3Enterprise,
                              .dynamicWEP].contains { n.supportsSecurity($0) }
                && ![CWSecurity.personal, .wpaPersonal, .wpaPersonalMixed, .wpa2Personal, .wpa3Personal, .wpa3Transition]
                    .contains { n.supportsSecurity($0) }
            let item = WiFiNetwork(ssid: s, rssi: n.rssiValue, secured: !n.supportsSecurity(.none), known: known.contains(s),
                                   enterprise: enterprise)
            if let old = best[s], old.rssi >= item.rssi { continue }
            best[s] = item
        }
        return best.values.sorted { ($0.ssid == current ? 0 : 1, -$0.rssi) < ($1.ssid == current ? 0 : 1, -$1.rssi) }
    }

    /// Joins a network. Returns an error message, or nil. Secured networks need the password, Enterprise ones the
    /// username too. A saved network can be tried with neither: macOS uses what it has stored.
    func join(_ network: WiFiNetwork, username: String? = nil, password: String?) async -> String? {
        joining = network.ssid; error = nil
        defer { joining = nil }
        let ssidData = Data(network.ssid.utf8)
        let message: String? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let iface = CWWiFiClient.shared().interface(),
                      let target = ((try? iface.scanForNetworks(withSSID: ssidData)) ?? []).first else {
                    cont.resume(returning: "\(network.ssid) isn't in range."); return
                }
                do {
                    if network.enterprise {
                        try iface.associate(toEnterpriseNetwork: target, identity: nil, username: username, password: password)
                    } else {
                        try iface.associate(to: target, password: password)
                    }
                    cont.resume(returning: nil)
                } catch {
                    let msg: String
                    if password == nil { msg = network.enterprise ? "Sign in to join." : "This network needs a password." }
                    else if network.enterprise { msg = "Couldn't sign in. Check the username and password, or use Wi-Fi Settings." }
                    else { msg = "Couldn't join. Check the password." }
                    cont.resume(returning: msg)
                }
            }
        }
        refresh()
        if message == nil { for _ in 0..<10 where ssid != network.ssid { try? await Task.sleep(for: .seconds(1)); refresh() } }
        self.error = message
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
            self.onConnected?(now, self.hotspot)
        }
    }
}
