import AppKit

struct FocusMode: Equatable {
    var id: String
    var name: String
    var symbol: String
}

/// The active Focus, read from the Do Not Disturb database (needs Full Disk Access). Read-only: macOS has no public
/// way to set a Focus. The folder is watched, and one change writes it several times, so reads are debounced.
@MainActor @Observable
final class FocusMonitor {
    private(set) var active: FocusMode?
    private(set) var accessGranted = false

    /// (previous, new) when the active Focus changed.
    @ObservationIgnored var onChange: ((FocusMode?, FocusMode?) -> Void)?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var debounce: Task<Void, Never>?

    private static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")

    func start() {
        let result = Self.read()
        accessGranted = result.granted
        active = result.mode
        watch()
    }

    /// Call after the user may have granted Full Disk Access.
    func retry() {
        let result = Self.read()
        accessGranted = result.granted
        if result.granted, source == nil { active = result.mode; watch() }
    }

    private func watch() {
        guard source == nil else { return }
        let fd = open(Self.dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func changed() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            let now = Self.read().mode
            guard now != self.active else { return }
            let old = self.active
            self.active = now
            self.onChange?(old, now)
        }
    }

    // MARK: Reading

    private static func read() -> (granted: Bool, mode: FocusMode?) {
        guard let assertions = try? Data(contentsOf: dir.appendingPathComponent("Assertions.json")) else { return (false, nil) }
        guard let json = try? JSONSerialization.jsonObject(with: assertions) as? [String: Any],
              let records = (json["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]],
              let id = records.compactMap({ ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }).first
        else { return (true, nil) }

        var name = id.split(separator: ".").last.map(String.init)?.capitalized ?? "Focus"
        var symbol = "moon.fill"
        if let data = try? Data(contentsOf: dir.appendingPathComponent("ModeConfigurations.json")),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cfgs = (j["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any],
           let mode = (cfgs[id] as? [String: Any])?["mode"] as? [String: Any] {
            if let n = mode["name"] as? String { name = n }
            if let s = mode["symbolImageName"] as? String, NSImage(systemSymbolName: s, accessibilityDescription: nil) != nil { symbol = s }
        }
        return (true, FocusMode(id: id, name: name, symbol: symbol))
    }
}
