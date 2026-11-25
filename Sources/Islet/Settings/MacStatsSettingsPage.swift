import SwiftUI

/// Settings > Mac Stats (DESIGN.md "Mac Stats (1.7)", Settings): the feature's switch, then what the menu bar shows,
/// part by part, and how it looks.
struct MacStatsSettingsPage: View {
    @AppStorage(MacStatsSettings.enabled) private var enabled = false
    @AppStorage(MacStatsSettings.meters) private var meters = true
    @AppStorage(MacStatsSettings.efficiency) private var efficiency = true
    @AppStorage(MacStatsSettings.performance) private var performance = true
    @AppStorage(MacStatsSettings.gpu) private var gpu = true
    @AppStorage(MacStatsSettings.memory) private var memory = true
    @AppStorage(MacStatsSettings.readouts) private var readouts = true
    @AppStorage(MacStatsSettings.temperature) private var temperature = true
    @AppStorage(MacStatsSettings.power) private var power = true
    @AppStorage(MacStatsSettings.fan) private var fan = true
    @AppStorage(MacStatsSettings.temperatureSource) private var source = TemperatureSource.cpuAverage.rawValue
    @AppStorage(MacStatsSettings.colourParts) private var colourParts = true
    @AppStorage(MacStatsSettings.warnings) private var warnings = true
    @AppStorage(MacStatsSettings.WarnPart.efficiency.key) private var warnEfficiency = true
    @AppStorage(MacStatsSettings.WarnPart.performance.key) private var warnPerformance = true
    @AppStorage(MacStatsSettings.WarnPart.gpu.key) private var warnGPU = true
    @AppStorage(MacStatsSettings.WarnPart.memory.key) private var warnMemory = true
    @AppStorage(MacStatsSettings.WarnPart.temperature.key) private var warnTemperature = true
    @AppStorage(MacStatsSettings.interval) private var interval = 2
    @AppStorage(FanControl.enabledKey) private var fanControl = false
    private let fans = FanControl.shared

    /// Nothing left on in the menu bar, so there's nowhere to open the stats from.
    private var nothingShows: Bool {
        !(meters && (efficiency || performance || gpu || memory)) && !(readouts && (temperature || power || fan))
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    SettingsLabel("Mac Stats", "CPU, GPU, memory, temperature, power and fans in the menu bar, with the details a click away. Off, nothing is measured.")
                }
            }

            Section {
                Toggle(isOn: $meters) {
                    SettingsLabel("Usage meters", "Bars for the CPU cores, GPU and memory. They turn yellow or red when a part is working hard.")
                }
                part("Efficiency cores", .efficiency, $efficiency, parent: meters)
                part("Performance cores", .performance, $performance, parent: meters)
                part("GPU", .gpu, $gpu, parent: meters)
                part("Memory", .memory, $memory, parent: meters)

                Toggle(isOn: $readouts) {
                    SettingsLabel("Temperature, power and fans", "A number for each, beside the meters.")
                }
                child("Temperature", $temperature, parent: readouts)
                Picker(selection: $source) {
                    Text("CPU average").tag(TemperatureSource.cpuAverage.rawValue)
                    Text("Hottest CPU core").tag(TemperatureSource.cpuHottest.rawValue)
                    Text("GPU").tag(TemperatureSource.gpu.rawValue)
                } label: {
                    indented { Text("Temperature shows") }
                }
                .disabled(!readouts || !temperature)
                child("Power", $power, parent: readouts)
                child("Fan speed", $fan, parent: readouts)
            } header: {
                Text("Menu Bar")
            } footer: {
                if enabled && nothingShows {
                    Text("Nothing is on in the menu bar, so there's nowhere to open the stats from.")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            .disabled(!enabled)

            Section {
                Toggle(isOn: $colourParts) {
                    SettingsLabel("Colour each part", "Efficiency cores green, performance cores blue, GPU purple, memory cyan. Off, the meters take the menu bar's colour, like the battery.")
                }
                Toggle(isOn: $warnings) {
                    SettingsLabel("Warn in yellow and red", "When a part works hard, memory is under pressure, or it's hot.")
                }
                part("Efficiency cores", .efficiency, $warnEfficiency, parent: warnings)
                part("Performance cores", .performance, $warnPerformance, parent: warnings)
                part("GPU", .gpu, $warnGPU, parent: warnings)
                part("Memory", .memory, $warnMemory, parent: warnings)
                child("Temperature", $warnTemperature, parent: warnings)
                Picker("Update every", selection: $interval) {
                    Text("Second").tag(1)
                    Text("2 seconds").tag(2)
                    Text("5 seconds").tag(5)
                }
            } header: {
                Text("Look")
            }
            .disabled(!enabled)

            Section {
                Toggle(isOn: $fanControl) {
                    SettingsLabel("Let me control the fans", "Adds Manual and Full Speed to the Fans page. They go back to Automatic when the Mac sleeps or Dynamic Peninsula quits, and macOS takes over if the Mac gets too hot.")
                }
                .onChange(of: fanControl) { _, on in if !on { fans.setAutomatic() } }
                if fanControl {
                    LabeledContent {
                        switch fans.helper {
                        case .ready: Button("Remove…") { fans.remove() }
                        case .needsApproval: Button("Open Login Items…") { fans.openLoginItems() }
                        case .notInstalled, .failed: Button("Install…") { fans.install() }
                        }
                    } label: {
                        SettingsLabel("Fan helper", helperDetail)
                    }
                }
            } header: {
                Text("Fan Control")
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .onAppear { fans.refresh() }
        // Allowing it happens in System Settings: look again when the window comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in fans.refresh() }
    }

    private var helperDetail: String {
        switch fans.helper {
        case .ready: "Installed. Changing fan speed needs this small helper, which runs as an administrator."
        case .needsApproval: "Waiting to be allowed in System Settings > General > Login Items, under Allow in the Background."
        case .notInstalled: "Changing fan speed needs a small helper that runs as an administrator. macOS asks you to allow it once."
        case .failed(let why): "Couldn't install it: \(why)"
        }
    }

    /// A meter's switch, tied to the row above it, with its colour: click the colour to pick another.
    private func part(_ title: String, _ part: MacStatsMenuBarContent.Part, _ on: Binding<Bool>, parent: Bool) -> some View {
        Toggle(isOn: on) {
            indented {
                HStack(spacing: 6) {
                    ColourSwatch(part: part, title: title)
                        .opacity(colourParts ? 1 : 0.35)
                    Text(title)
                }
            }
        }
        .disabled(!parent)
    }

    private func child(_ title: String, _ on: Binding<Bool>, parent: Bool) -> some View {
        Toggle(isOn: on) { indented { Text(title) } }.disabled(!parent)
    }

    /// Part of the row above: an arrow turning down and in, as Messages under Notifications.
    private func indented(@ViewBuilder _ label: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.callout.weight(.medium)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            label()
        }
    }
}

/// A part's colour as a small square; clicking it opens the sixteen to choose from (`MacStatsPalette`).
private struct ColourSwatch: View {
    let part: MacStatsMenuBarContent.Part
    let title: String
    @AppStorage private var chosen: Int
    @State private var open = false

    init(part: MacStatsMenuBarContent.Part, title: String) {
        self.part = part
        self.title = title
        _chosen = AppStorage(wrappedValue: MacStatsPalette.defaultIndex(part), MacStatsPalette.key(part))
    }

    private var index: Int { MacStatsPalette.all.indices.contains(chosen) ? chosen : MacStatsPalette.defaultIndex(part) }

    var body: some View {
        Button { open = true } label: {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(colour(MacStatsPalette.all[index]))
                .frame(width: 9, height: 9)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Change the colour")
        .accessibilityLabel("\(title) colour, \(MacStatsPalette.all[index].name)")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(MacStatsPalette.all.enumerated()), id: \.offset) { i, swatch in
                    Button {
                        chosen = i
                        open = false
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colour(swatch))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if i == index {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                }
            }
            .padding(12)
        }
    }

    /// As it looks in the menu bar now: the bright one on dark, the deep one on light.
    private func colour(_ s: MacStatsPalette.Swatch) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let hex = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? s.dark : s.light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}
