import AppKit
import CoreLocation
import CoreWLAN

struct WiFiNetwork: Identifiable, Equatable {
    var ssid: String
    var rssi: Int
    var secured: Bool
    var known: Bool
    var id: String { ssid }
    /// 1...3 bars.
    var bars: Int { rssi > -60 ? 3 : (rssi > -72 ? 2 : 1) }
}

/// Wi-Fi: power, the connected network, nearby networks and joining (CoreWLAN). Network names need Location
/// Services. Events fire when the connected network changes (debounced, never for nil).
@MainActor @Observable
final class WiFiController: NSObject, CWEventDelegate, CLLocationManagerDelegate {
    private(set) var powerOn = false
    private(set) var ssid: String?
    private(set) var networks: [WiFiNetwork] = []
    private(set) var scanning = false
    private(set) var joining: String?
    private(set) var locationStatus = CLAuthorizationStatus.notDetermined
    var error: String?

    @ObservationIgnored var onConnected: ((String) -> Void)?
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
    }

    func refresh() {
        locationStatus = location.authorizationStatus
        let i = CWWiFiClient.shared().interface()
        powerOn = i?.powerOn() ?? false
        ssid = powerOn ? i?.ssid() : nil
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
            let item = WiFiNetwork(ssid: s, rssi: n.rssiValue, secured: !n.supportsSecurity(.none), known: known.contains(s))
            if let old = best[s], old.rssi >= item.rssi { continue }
            best[s] = item
        }
        return best.values.sorted { ($0.ssid == current ? 0 : 1, -$0.rssi) < ($1.ssid == current ? 0 : 1, -$1.rssi) }
    }

    /// Joins a network. Returns an error message, or nil. Secured networks need the password.
    func join(_ network: WiFiNetwork, password: String?) async -> String? {
        joining = network.ssid; error = nil
        defer { joining = nil }
        let ssidData = Data(network.ssid.utf8)
        let message: String? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let iface = CWWiFiClient.shared().interface(),
                      let target = ((try? iface.scanForNetworks(withSSID: ssidData)) ?? []).first else {
                    cont.resume(returning: "\(network.ssid) isn't in range."); return
                }
                do { try iface.associate(to: target, password: password); cont.resume(returning: nil) }
                catch { cont.resume(returning: (error as NSError).code == -3900 || password != nil ? "Couldn't join. Check the password." : "This network needs a password.") }
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
            self.lastAnnounced = now
            self.onConnected?(now)
        }
    }
}
