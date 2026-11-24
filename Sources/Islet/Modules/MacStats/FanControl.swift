import Foundation
import Observation
import ServiceManagement

/// Manual fan control (DESIGN.md "Mac Stats (1.7)", Fans page): installs the root fan helper with `SMAppService`, asks
/// it for Automatic, a speed, or Full Speed, and checks in while it holds the fans, so the helper gives them back as soon
/// as the app goes away (RESEARCH.md "Mac Stats").
@MainActor @Observable
final class FanControl {
    static let shared = FanControl()

    /// Settings > Mac Stats > "Let me control the fans".
    static let enabledKey = "macStatsFanControl"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    enum Helper: Equatable {
        case notInstalled
        /// Registered; waiting for the switch in System Settings > General > Login Items.
        case needsApproval
        case ready
        case failed(String)
    }

    enum Mode: Equatable {
        case automatic
        case manual(rpm: Double)
        case full
    }

    private(set) var helper: Helper = .notInstalled
    private(set) var mode: Mode = .automatic
    /// Taking the fans over takes a few seconds the first time.
    private(set) var busy = false
    /// What went wrong last, or why the helper gave the fans back on its own.
    private(set) var note: String?

    @ObservationIgnored private var connection: NSXPCConnection?
    /// Counts requests, so an older one's late answer can't undo a newer choice.
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private let service = SMAppService.daemon(plistName: FanHelperInfo.plistName)

    init() { refresh() }

    /// Re-reads the helper's registration (it can change in System Settings at any time).
    func refresh() {
        switch service.status {
        case .enabled: helper = .ready
        case .requiresApproval: helper = .needsApproval
        case .notRegistered, .notFound: helper = .notInstalled
        @unknown default: helper = .notInstalled
        }
        if helper != .ready { dropConnection() }
    }

    /// Registers the helper. macOS then asks for it to be allowed in Login Items, which takes the admin password.
    func install() {
        do {
            try service.register()
        } catch {
            // Already registered but not yet allowed comes back as an error too.
            if service.status != .requiresApproval { helper = .failed(error.localizedDescription) }
        }
        refresh()
        if helper == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    /// Gives the fans back first, then removes the helper.
    func remove() {
        setAutomatic { [weak self] in
            guard let self else { return }
            self.dropConnection()
            try? self.service.unregister()
            self.refresh()
        }
    }

    // MARK: - Fans

    func setAutomatic(then done: (() -> Void)? = nil) {
        request += 1
        stopHeartbeat()
        mode = .automatic
        busy = false
        note = nil
        guard let proxy = proxy() else { done?(); return }
        proxy.setAutomatic { _ in Task { @MainActor in done?() } }
    }

    /// Both fans at `rpm`. A change while already manual is quick; the first takes a few seconds.
    func setManual(rpm: Double) {
        mode = .manual(rpm: rpm)
        send { proxy, reply in proxy.setSpeed(rpm, reply: reply) }
    }

    func setFull() {
        mode = .full
        send { proxy, reply in proxy.setFullSpeed(reply: reply) }
    }

    private func send(_ call: (FanHelperProtocol, @escaping (Bool, String?) -> Void) -> Void) {
        guard let proxy = proxy() else { mode = .automatic; return }
        request += 1
        let sent = request
        busy = true
        note = nil
        startHeartbeat()
        call(proxy) { [weak self] ok, message in
            Task { @MainActor [weak self] in
                // Only the newest request's answer counts: one pressed over says nothing about the fans now.
                guard let self, sent == self.request else { return }
                self.busy = false
                if !ok {
                    self.note = message ?? "The fans couldn't be changed."
                    self.mode = .automatic
                    self.stopHeartbeat()
                }
            }
        }
    }

    /// Checks in while the helper holds the fans, and notices when it gave them back on its own (the Mac got hot).
    private func startHeartbeat() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(FanHelperInfo.heartbeatInterval))
                guard let self, !Task.isCancelled, let proxy = self.proxy() else { return }
                proxy.heartbeat()
                let asked = self.request
                proxy.status { [weak self] status in
                    let helperMode = status[FanHelperStatus.mode] as? String
                    let reason = status[FanHelperStatus.reason] as? String
                    Task { @MainActor [weak self] in
                        guard let self, !self.busy, asked == self.request, helperMode == "automatic", self.mode != .automatic else { return }
                        self.mode = .automatic
                        self.note = reason
                        self.stopHeartbeat()
                    }
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func proxy() -> FanHelperProtocol? {
        guard helper == .ready else { return nil }
        if connection == nil {
            let c = NSXPCConnection(machServiceName: FanHelperInfo.machService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
            // Only our own helper.
            c.setCodeSigningRequirement(FanHelperInfo.helperRequirement)
            // The helper went away: it gives the fans back when it starts again, so they're automatic.
            let lost: @Sendable () -> Void = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.connection = nil
                    if self.mode != .automatic {
                        self.mode = .automatic
                        self.note = "The fan helper stopped, so macOS has the fans again."
                    }
                    self.busy = false
                    self.stopHeartbeat()
                }
            }
            c.invalidationHandler = lost
            c.interruptionHandler = lost
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.busy = false
                self?.note = "The fan helper didn't answer: \(error.localizedDescription)"
            }
        } as? FanHelperProtocol
    }

    private func dropConnection() {
        stopHeartbeat()
        connection?.invalidate()
        connection = nil
        mode = .automatic
    }
}
