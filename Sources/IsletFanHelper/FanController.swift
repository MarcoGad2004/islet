import Foundation

/// Holds the fans at a speed and always gives them back. Everything runs on one serial queue.
///
/// Taking over (RESEARCH.md "Mac Stats", spike results): `Ftst` = 1 (the test unlock), then each fan's mode `F<n>Md` = 1,
/// which the SMC refuses for about 6 s after the unlock, then the target `F<n>Tg`. Giving back: every target to 0 and
/// `Ftst` = 0; the SMC puts the modes back to automatic itself within a few seconds.
///
/// It gives the fans back when the app goes away or stops checking in, when the CPU gets hot, before sleep, on SIGTERM,
/// and once when it starts, in case a crash left them held.
final class FanController {
    enum Mode: String { case automatic, manual, full }

    let queue = DispatchQueue(label: "com.marcogad.islet.fanhelper.smc")
    private let smc: SMC
    private let fans: Int
    private let cpuKeys: [String]
    private(set) var mode: Mode = .automatic
    private var rpm: Double = 0
    private var lastHeard = Date()
    private var reason: String?
    private var timer: DispatchSourceTimer?
    /// Connections from the app that are open.
    var connections = 0 {
        didSet { if connections == 0 { idleSince = Date(); handBack("Dynamic Peninsula closed") } }
    }
    private var idleSince = Date()

    init?() {
        guard let smc = SMC() else { return nil }
        self.smc = smc
        fans = Int(smc.number("FNum") ?? 0)
        cpuKeys = smc.allKeys().filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
    }

    func start() {
        queue.sync { handBack(nil, force: true) }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 2)
        t.setEventHandler { [weak self] in self?.check() }
        t.resume()
        timer = t
    }

    func status() -> NSDictionary {
        var d: [String: Any] = [FanHelperStatus.mode: mode.rawValue, FanHelperStatus.rpm: rpm,
                                FanHelperStatus.version: FanHelperInfo.version]
        if let reason { d[FanHelperStatus.reason] = reason }
        return d as NSDictionary
    }

    func heard() { lastHeard = Date() }

    /// Both fans at `target`, kept within each fan's range; `nil` is full speed.
    func set(_ target: Double?) -> (Bool, String?) {
        guard fans > 0 else { return (false, "This Mac has no fans.") }
        lastHeard = Date()
        reason = nil
        if mode == .automatic {
            guard smc.write("Ftst", [1]) else { return (false, "The fans can't be changed.") }
            // The mode is refused for a few seconds after the unlock (about 6 s on an M4 Pro).
            var taken = false
            for _ in 0..<30 where !taken {
                taken = (0..<fans).allSatisfy { smc.write("F\($0)Md", [1]) }
                if !taken { Thread.sleep(forTimeInterval: 0.5) }
            }
            guard taken else {
                handBack(nil, force: true)
                return (false, "macOS didn't hand over the fans.")
            }
        }
        var ok = true
        for i in 0..<fans {
            let lo = smc.number("F\(i)Mn") ?? 0, hi = smc.number("F\(i)Mx") ?? 0
            let value = target.map { min(max($0, lo), hi) } ?? hi
            ok = smc.writeFloat("F\(i)Tg", value) && ok
        }
        mode = target == nil ? .full : .manual
        rpm = target ?? (smc.number("F0Mx") ?? 0)
        return (ok, ok ? nil : "A fan didn't take the new speed.")
    }

    /// Gives the fans back to macOS. `reason` says why when the helper did it on its own.
    func handBack(_ reason: String?, force: Bool = false) {
        guard mode != .automatic || force else { return }
        for i in 0..<max(fans, 0) { _ = smc.writeFloat("F\(i)Tg", 0) }
        smc.write("Ftst", [0])
        if mode != .automatic, let reason { self.reason = reason }
        mode = .automatic
        rpm = 0
    }

    private func check() {
        if mode != .automatic {
            if Date().timeIntervalSince(lastHeard) > FanHelperInfo.heartbeatTimeout {
                handBack("Dynamic Peninsula stopped answering")
            } else if let t = cpuAverage(), t >= FanHelperInfo.handBackCelsius {
                handBack("The Mac got hot, so macOS took the fans back")
            }
        } else if connections == 0, Date().timeIntervalSince(idleSince) > 60 {
            // Nothing to do: launchd starts it again when the app next connects.
            exit(0)
        }
    }

    private func cpuAverage() -> Double? {
        let xs = cpuKeys.compactMap { smc.number($0) }.filter { $0 >= 10 && $0 < 130 }
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }
}
