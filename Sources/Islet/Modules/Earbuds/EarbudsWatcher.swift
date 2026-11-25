import AppKit
import CoreBluetooth

/// What AirPods in an open case say about themselves: the model, each part's charge and whether it is charging.
struct EarbudsReading: Equatable, Sendable {
    /// Apple's two-byte model code from the broadcast.
    var model: UInt16
    var name: String
    /// Pro-style earbuds (silicone tips) or the stemmed AirPods: which shape the animation draws.
    var pro: Bool
    /// The lower of the two earbuds' charge, in percent; nil when neither is in the case to report it.
    var earbuds: Int?
    var caseLevel: Int?
    var earbudsCharging: Bool
    var caseCharging: Bool

    /// The model codes seen in the broadcast (RESEARCH.md Q28). An unknown code still shows, as plain "AirPods".
    static let models: [UInt16: (name: String, pro: Bool)] = [
        0x2002: ("AirPods", false), 0x200F: ("AirPods 2", false), 0x2013: ("AirPods 3", false),
        0x2019: ("AirPods 4", false), 0x201B: ("AirPods 4", false),
        0x200E: ("AirPods Pro", true), 0x2014: ("AirPods Pro 2", true), 0x2024: ("AirPods Pro 2", true),
        0x2027: ("AirPods Pro 3", true),
    ]

    /// The SF Symbols for this model's earbuds and case (Apple's own drawings of each generation).
    var symbols: (earbuds: String, pod: String) {
        switch model {
        case 0x2013: ("airpods.gen3", "airpods.gen3.chargingcase.wireless.fill")
        case 0x2019, 0x201B: ("airpods.gen4", "airpods.gen4.chargingcase.wireless.fill")
        case 0x2027: ("airpods.pro.gen3", "airpodspro.chargingcase.wireless.fill")
        case 0x2002, 0x200F: ("airpods", "airpods.chargingcase.wireless.fill")
        default: pro ? ("airpodspro", "airpodspro.chargingcase.wireless.fill") : ("airpods", "airpods.chargingcase.wireless.fill")
        }
    }

    /// Reads one Apple "proximity pairing" broadcast (company 0x004C, type 0x07, 29 bytes). `open` is the case's lid
    /// (bit 3 of byte 10: clear while open, set in the burst as it closes). Earbuds on their own, in the ears, send
    /// the same message with the case's charge unknown (nibble 0xF): not a case, so nil.
    static func decode(_ d: Data) -> (reading: EarbudsReading, open: Bool)? {
        guard d.count >= 12, d[0] == 0x4C, d[1] == 0x00, d[2] == 0x07, d[3] >= 0x19 else { return nil }
        let model = UInt16(d[6]) << 8 | UInt16(d[5])
        let caseNibble = Int(d[9] & 0x0F)
        guard caseNibble <= 10 else { return nil }
        let flags = d[9] >> 4
        let left = Int(d[8] >> 4), right = Int(d[8] & 0x0F)
        let levels = [left, right].filter { $0 <= 10 }.map { $0 * 10 }
        let info = models[model] ?? ("AirPods", false)
        let reading = EarbudsReading(model: model, name: info.name, pro: info.pro, earbuds: levels.min(), caseLevel: caseNibble * 10,
                                     earbudsCharging: flags & 0x3 != 0, caseCharging: flags & 0x4 != 0)
        return (reading, d[10] & 0x08 == 0)
    }
}

/// Listens for the broadcast an AirPods case sends while its lid is open (RESEARCH.md Q28), to show the island's
/// case card. Only Bluetooth advertisements are read, nothing is connected to, and nothing leaves the Mac. Other
/// people's cases are heard too, so only the strongest source, a few inches away, counts.
final class EarbudsWatcher: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    /// The case that's open next to the Mac (nil once it closes). Called on the main actor.
    var onChange: (@MainActor (EarbudsReading?) -> Void)?

    private let queue = DispatchQueue(label: "islet.earbuds", qos: .utility)
    private var central: CBCentralManager?
    private var wanted = false
    private var scanning = false
    private var screenOn = true
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    private struct Seen { var reading: EarbudsReading; var open: Bool; var rssi: Double; var at: Date }
    private var seen: [UUID: Seen] = [:]
    private var shown: EarbudsReading?

    /// Closer than about two feet. A case in someone else's hands a desk away reads weaker than this.
    private static let nearest = -58.0
    private static let silence: TimeInterval = 3

    func start() {
        queue.async { [self] in
            guard !wanted else { return }
            wanted = true
            let nc = NSWorkspace.shared.notificationCenter
            observers = [
                nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { self?.screenOn = false; self?.update() }
                },
                nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { self?.screenOn = true; self?.update() }
                },
            ]
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1)
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
            update()
        }
    }

    func stop() {
        queue.async { [self] in
            wanted = false
            observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            observers = []
            timer?.cancel(); timer = nil
            update()
        }
    }

    /// Bluetooth is only touched once its access is already allowed (the Bluetooth list asks for it), so this never
    /// raises a prompt of its own.
    private func update() {
        let allowed = CBManager.authorization == .allowedAlways
        if wanted, allowed, central == nil { central = CBCentralManager(delegate: self, queue: queue) }
        guard let central else { return }
        let should = wanted && allowed && screenOn && central.state == .poweredOn
        if should, !scanning {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            scanning = true
        } else if !should, scanning {
            central.stopScan()
            scanning = false
            seen = [:]
            publish(nil)
        }
        if !wanted { self.central = nil }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) { update() }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard rssi.intValue != 127,
              let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let (reading, open) = EarbudsReading.decode(data) else { return }
        let id = peripheral.identifier
        let strength = rssi.doubleValue
        let smoothed = seen[id].map { 0.6 * $0.rssi + 0.4 * strength } ?? strength
        seen[id] = Seen(reading: reading, open: open, rssi: smoothed, at: Date())
        evaluate()
    }

    private func tick() {
        if !wanted || !scanning { update(); return }
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value.at) < 10 }
        evaluate()
    }

    /// The nearest recent source decides: open shows its reading, closed (or silent) takes the card away.
    private func evaluate() {
        let now = Date()
        let near = seen.values.filter { now.timeIntervalSince($0.at) < Self.silence && $0.rssi >= Self.nearest }
        if let best = near.max(by: { $0.rssi < $1.rssi }), best.open { publish(best.reading) } else { publish(nil) }
    }

    private func publish(_ reading: EarbudsReading?) {
        guard reading != shown else { return }
        shown = reading
        Task { @MainActor [weak self] in self?.onChange?(reading) }
    }
}
