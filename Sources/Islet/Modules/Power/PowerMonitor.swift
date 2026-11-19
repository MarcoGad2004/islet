import Foundation
import IOKit.ps

/// Battery and charger state from IOKit, driven by power-source notifications (no polling).
@MainActor @Observable
final class PowerMonitor {
    struct State: Equatable {
        var percent = 100
        var onAC = false
        var charging = false
        var charged = false
        var minutesToFull: Int?
        var minutesToEmpty: Int?
        var hasBattery = true
    }

    private(set) var state = State()
    @ObservationIgnored var onEvent: ((ChargeEvent) -> Void)?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var delayed: Task<Void, Never>?

    func start() {
        state = Self.read()
        started = true
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.changed() }
        }, ctx)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    func refresh() { state = Self.read() }

    private func changed() {
        let old = state
        let new = Self.read()
        state = new
        guard started, new.hasBattery else { return }

        if new.onAC && !old.onAC {
            // Time to full is often unknown for a second after plugging in.
            delayed?.cancel()
            delayed = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.0))
                guard let self, !Task.isCancelled else { return }
                let s = Self.read()
                state = s
                if s.charged { onEvent?(ChargeEvent(kind: .full, percent: s.percent)) }
                else { onEvent?(ChargeEvent(kind: .connected, percent: s.percent, minutesToFull: s.minutesToFull)) }
            }
        } else if new.onAC && new.charged && !old.charged {
            onEvent?(ChargeEvent(kind: .full, percent: new.percent))
        } else if !new.onAC && !new.charging {
            // Low battery only when not charging: once at 20% and once at 10%.
            for threshold in [20, 10] where old.percent > threshold && new.percent <= threshold {
                onEvent?(ChargeEvent(kind: .low, percent: new.percent))
                break
            }
        }
    }

    private static func read() -> State {
        var s = State()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { s.hasBattery = false; return s }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            s.percent = d[kIOPSCurrentCapacityKey] as? Int ?? 100
            s.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            s.charging = d[kIOPSIsChargingKey] as? Bool ?? false
            s.charged = (d[kIOPSIsChargedKey] as? Bool ?? false) || (s.onAC && s.percent >= 100)
            if let t = d[kIOPSTimeToFullChargeKey] as? Int, t > 0 { s.minutesToFull = t }
            if let t = d[kIOPSTimeToEmptyKey] as? Int, t > 0 { s.minutesToEmpty = t }
            return s
        }
        s.hasBattery = false
        return s
    }
}
