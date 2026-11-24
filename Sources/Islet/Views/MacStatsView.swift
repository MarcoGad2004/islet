import SwiftUI

/// Which page the Mac Stats panel shows. Kept outside the view so each opening starts on the overview.
enum MacStatsPage: Equatable { case overview, cpu, memory, gpu, fans }

@MainActor @Observable
final class MacStatsPanelState {
    var page: MacStatsPage = .overview
}

/// Mac Stats' panel (DESIGN.md "Mac Stats (1.7)", Panel): the overview, and a page for the CPU, memory, the GPU and the
/// fans that glides in over it.
struct MacStatsView: View {
    let stats: MacStats
    let state: MacStatsPanelState
    /// The page on screen. A new one waits until the old has faded out, so only one is ever laid out and the panel
    /// changes size once, while nothing shows.
    @State private var shown: MacStatsPage?
    @State private var opacity = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch shown ?? state.page {
            case .overview: MacStatsOverview(stats: stats, open: { state.page = $0 })
            case .cpu: MacStatsCPUPage(stats: stats, back: back)
            case .memory: MacStatsMemoryPage(stats: stats, back: back)
            case .gpu: MacStatsGPUPage(stats: stats, back: back)
            case .fans: MacStatsFansPage(stats: stats, back: back)
            }
        }
        .opacity(opacity)
        .padding(16)
        .frame(width: 300, alignment: .topLeading)
        // Each reading glides in, like the battery stats' power flow: numbers roll, bars and charts ease to it.
        // Nothing rolls or glides with Reduce Motion: the new readings just show.
        .animation(reduceMotion ? nil : MacStatsMotion.reading, value: stats.snapshot.date)
        .onChange(of: state.page, initial: true) { _, page in
            stats.wantsProcesses = [.cpu, .memory, .gpu].contains(page)
        }
        .onChange(of: state.page) { _, _ in
            // A plain fade (DESIGN.md "Mac Stats (1.7)", Motion): out, swap, in. The new page fades in on the same
            // curve and at the same time as the panel eases to its size, so the two read as one movement.
            withAnimation(.easeIn(duration: 0.1)) { opacity = 0 } completion: {
                shown = state.page
                withAnimation(MacStatsMotion.settle) { opacity = 1 }
            }
        }
    }

    private func back() { state.page = .overview }
}

extension MacStatsView {
    @MainActor private static var warmed = false

    /// Renders each page once off screen: the first showing of a page otherwise stalls a moment loading its fonts and
    /// symbols, which showed as a flicker on the first page opened.
    @MainActor static func warmUp() {
        guard !warmed else { return }
        warmed = true
        let stats = MacStats.shared
        let pages: [AnyView] = [
            AnyView(MacStatsOverview(stats: stats, open: { _ in })),
            AnyView(MacStatsCPUPage(stats: stats, back: {})),
            AnyView(MacStatsMemoryPage(stats: stats, back: {})),
            AnyView(MacStatsGPUPage(stats: stats, back: {})),
            AnyView(MacStatsFansPage(stats: stats, back: {})),
        ]
        for page in pages {
            _ = ImageRenderer(content: page.padding(16).frame(width: 300)).nsImage
        }
    }
}

// MARK: - Overview

private struct MacStatsOverview: View {
    let stats: MacStats
    let open: (MacStatsPage) -> Void

    var body: some View {
        let s = stats.snapshot
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mac").font(.system(size: 15, weight: .bold)).foregroundStyle(IsletInk.primary)
                Spacer()
                if let up = MacStatsFormat.uptime() {
                    Text(up).font(.system(size: 13)).foregroundStyle(IsletInk.secondary)
                }
            }
            .padding(.bottom, 12)

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Tile(title: "CPU", value: MacStatsFormat.percent(s.cpu?.total), number: s.cpu?.total,
                         level: StatLevel(load: max(s.cpu?.efficiency ?? 0, s.cpu?.performance ?? 0)), action: { open(.cpu) }) {
                        VStack(spacing: 6) {
                            CoreTypeRow(letter: "E", value: s.cpu?.efficiency, colour: MacStatsColour.efficiency)
                            CoreTypeRow(letter: "P", value: s.cpu?.performance, colour: MacStatsColour.performance)
                        }
                        .padding(.top, 6)
                    }
                    Tile(title: "GPU", value: MacStatsFormat.percent(s.gpu?.utilization), number: s.gpu?.utilization,
                         level: StatLevel(load: s.gpu?.utilization ?? 0), action: { open(.gpu) }) {
                        Caption(s.gpu.map { "\(MacStatsFormat.megabytes($0.memoryInUse)) in use" } ?? " ")
                        let gpu = stats.buckets
                        Sparkline(values: gpu.map(\.gpu), newest: gpu.last?.date, top: 1, colour: MacStatsColour.gpu)
                    }
                }
                GridRow {
                    Tile(title: "Memory", value: MacStatsFormat.percent(s.memory?.fraction), number: s.memory?.fraction,
                         level: StatLevel(s.memory?.pressure ?? .normal), action: { open(.memory) }) {
                        Caption(s.memory.map { "\(MacStatsFormat.gigabytes($0.used)) of \(MacStatsFormat.gigabytes($0.total, decimals: 0))" } ?? " ")
                        if let m = s.memory { MemoryBar(memory: m, height: 6).padding(.top, 8) }
                        Text("Pressure \(MacStatsFormat.pressure(s.memory?.pressure ?? .normal))")
                            .font(.system(size: 11))
                            .foregroundStyle(MacStatsColour.level(StatLevel(s.memory?.pressure ?? .normal)) ?? Color(nsColor: .tertiaryLabelColor))
                            .padding(.top, 6)
                    }
                    Tile(title: "Power", value: MacStatsFormat.watts(s.systemWatts), number: s.systemWatts, level: .normal, action: nil) {
                        Caption(s.energy.map { "CPU \(MacStatsFormat.number($0.cpu)) · GPU \(MacStatsFormat.number($0.gpu)) W" } ?? " ")
                        let power = stats.buckets.filter { $0.watts != nil }
                        let watts = power.compactMap(\.watts)
                        Sparkline(values: watts, newest: power.last?.date, top: max(watts.max() ?? 1, 1) * 1.15, colour: nil)
                    }
                }
            }

            Rule()
            StatsSectionLabel("Temperature")
            VStack(spacing: 7) {
                StatRow("CPU", MacStatsFormat.temperature(s.thermal.cpuAverage),
                        colour: s.thermal.cpuAverage.flatMap { MacStatsColour.level(StatLevel(celsius: $0)) }, number: s.thermal.cpuAverage)
                StatRow("GPU", MacStatsFormat.temperature(s.thermal.gpuAverage),
                        colour: s.thermal.gpuAverage.flatMap { MacStatsColour.level(StatLevel(celsius: $0)) }, number: s.thermal.gpuAverage)
                if s.thermal.ssd != nil { StatRow("SSD", MacStatsFormat.temperature(s.thermal.ssd), number: s.thermal.ssd) }
            }

            if !s.fans.isEmpty {
                Rule()
                HStack {
                    Text("Fans").font(.system(size: 13)).foregroundStyle(IsletInk.secondary)
                    Spacer()
                    Pill(title: s.fansHeld ? "Manual" : "Automatic", chevron: true) { open(.fans) }
                }
                .padding(.bottom, 8)
                VStack(spacing: 7) {
                    ForEach(Array(s.fans.enumerated()), id: \.offset) { i, fan in
                        StatRow(MacStatsFormat.fanName(i, of: s.fans.count), MacStatsFormat.rpm(fan.rpm), number: fan.rpm)
                    }
                }
            }

            Rule()
            Footer()
        }
    }
}

private struct Tile<Content: View>: View {
    let title: String
    let value: String
    /// What `value` shows, so its digits roll up as it rises and down as it falls.
    let number: Double?
    let level: StatLevel
    let action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let body = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(IsletInk.secondary)
                if action != nil {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(IsletInk.tertiary)
                }
            }
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(MacStatsColour.level(level) ?? Color(nsColor: .labelColor))
                .rolls(number)
            content
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(IsletCard(shape: shape))
        .contentShape(shape)
        if let action {
            Button(action: action) { body }.buttonStyle(StatsPressStyle(shape: shape))
        } else {
            body
        }
    }
}

private struct CoreTypeRow: View {
    let letter: String
    let value: Double?
    let colour: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(letter).font(.system(size: 11, weight: .bold)).foregroundStyle(colour).frame(width: 9, alignment: .leading)
            MeterBar(fraction: value ?? 0, colour: colour)
            Text(MacStatsFormat.percent(value)).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(IsletInk.primary).frame(width: 30, alignment: .trailing)
                .rolls(value)
        }
    }
}

// MARK: - CPU

private struct MacStatsCPUPage: View {
    let stats: MacStats
    let back: () -> Void

    var body: some View {
        let s = stats.snapshot
        let cores = s.cpu?.cores.count ?? 1, eCount = s.cpu?.efficiencyCount ?? 0
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "CPU", trailing: MacStatsFormat.percent(s.cpu?.total), number: s.cpu?.total, back: back)
            HStack(spacing: 0) {
                Text("Last 10 minutes").font(.system(size: 13)).foregroundStyle(IsletInk.secondary).fixedSize()
                Spacer(minLength: 4)
                if eCount > 0 { Legend(name: "Efficiency", colour: MacStatsColour.efficiency) }
                Legend(name: "Performance", colour: MacStatsColour.performance)
            }
            let points = stats.buckets
            let perf = (colour: MacStatsColour.performance,
                        values: points.map { $0.performance * Double(cores - eCount) / Double(cores) })
            let eff = (colour: MacStatsColour.efficiency,
                       values: points.map { $0.efficiency * Double(eCount) / Double(cores) })
            LoadChart(layers: (eCount > 0 ? [eff] : []) + [perf], newest: points.last?.date)
                .padding(.top, 8)

            Rule()
            StatsSectionLabel("Cores")
            if let cpu = s.cpu {
                HStack(alignment: .bottom, spacing: 14) {
                    if cpu.efficiencyCount > 0 {
                        CoreGroup(name: "Efficiency", cores: Array(cpu.cores.prefix(cpu.efficiencyCount)), total: cpu.efficiency,
                                  colour: MacStatsColour.efficiency)
                    }
                    CoreGroup(name: "Performance", cores: Array(cpu.cores.dropFirst(cpu.efficiencyCount)), total: cpu.performance,
                              colour: MacStatsColour.performance)
                }
            }
            VStack(spacing: 7) {
                StatRow("User · System", "\(MacStatsFormat.percent(s.cpu?.user)) · \(MacStatsFormat.percent(s.cpu?.system))")
                StatRow("Temperature", MacStatsFormat.temperatures(s.thermal.cpuAverage, hottest: s.thermal.cpuHottest))
            }
            .padding(.top, 12)

            Rule()
            StatsSectionLabel("Using the most")
            // A few more than are shown, so one just under the fifth doesn't push in on a small difference.
            ProcessList(groups: ProcessNames.group(s.topCPU, limit: 8), empty: "Reading…", format: MacStatsFormat.share,
                        gap: 0.02, stoppable: true)
            Caption("100% is one core: a busy app can pass it.").padding(.top, 8)
            Rule()
            Footer()
        }
    }
}

private struct CoreGroup: View {
    let name: String
    let cores: [Double]
    let total: Double
    let colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(cores.enumerated()), id: \.offset) { _, load in
                    VBar(fraction: load, colour: MacStatsColour.level(StatLevel(load: load)) ?? colour)
                        .frame(width: 12, height: 36)
                }
            }
            HStack(spacing: 3) {
                Text(name).foregroundStyle(colour)
                Text(MacStatsFormat.percent(total)).foregroundStyle(IsletInk.primary).monospacedDigit()
                    .rolls(total)
            }
            .font(.system(size: 11))
        }
    }
}

// MARK: - Memory

private struct MacStatsMemoryPage: View {
    let stats: MacStats
    let back: () -> Void

    var body: some View {
        let s = stats.snapshot
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Memory",
                       trailing: s.memory.map { "\(MacStatsFormat.gigabytes($0.used)) of \(MacStatsFormat.gigabytes($0.total, decimals: 0))" } ?? "–",
                       number: s.memory.map { Double($0.used) }, back: back)
            HStack {
                Text("Last 10 minutes").font(.system(size: 13)).foregroundStyle(IsletInk.secondary)
                Spacer()
                Text(MacStatsFormat.pressure(s.memory?.pressure ?? .normal).capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacStatsColour.level(StatLevel(s.memory?.pressure ?? .normal)) ?? Color(nsColor: .labelColor))
            }
            MemoryChart(points: stats.buckets)
                .padding(.top, 8)
            Caption("Full is fine: macOS keeps spare memory busy. The colour is pressure, how hard it's working to find room.")
                .padding(.top, 8)

            Rule()
            if let m = s.memory {
                MemoryBar(memory: m, height: 8)
                VStack(spacing: 7) {
                    KeyRow("Apps", MacStatsFormat.gigabytes(m.app), MacStatsColour.memory, number: Double(m.app))
                    KeyRow("Kept for macOS", MacStatsFormat.gigabytes(m.wired), MacStatsColour.memory.opacity(0.6), number: Double(m.wired))
                    KeyRow("Compressed", MacStatsFormat.gigabytes(m.compressed), MacStatsColour.memory.opacity(0.35),
                           number: Double(m.compressed))
                    KeyRow("Free", MacStatsFormat.gigabytes(m.free), Color(nsColor: .quaternaryLabelColor), number: Double(m.free))
                    KeyRow("Swap used", MacStatsFormat.megabytesOrGigabytes(Double(m.swapUsed)), nil, number: Double(m.swapUsed))
                }
                .padding(.top, 10)
            }

            Rule()
            StatsSectionLabel("Using the most")
            ProcessList(groups: ProcessNames.group(s.topMemory, limit: 8), empty: "Reading…",
                        format: MacStatsFormat.megabytesOrGigabytes, gap: 50 * 1_048_576, stoppable: true)
            Rule()
            Footer()
        }
    }
}

/// Apps, kept for macOS and compressed, in shades of the memory colour, out of the whole.
private struct MemoryBar: View {
    let memory: MemorySample
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let total = max(Double(memory.total), 1), w = geo.size.width
            HStack(spacing: 1.5) {
                Rectangle().fill(MacStatsColour.memory).frame(width: w * Double(memory.app) / total)
                Rectangle().fill(MacStatsColour.memory.opacity(0.6)).frame(width: w * Double(memory.wired) / total)
                Rectangle().fill(MacStatsColour.memory.opacity(0.35)).frame(width: w * Double(memory.compressed) / total)
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(IsletInk.faint)
        .clipShape(Capsule())
    }
}

// MARK: - GPU

private struct MacStatsGPUPage: View {
    let stats: MacStats
    let back: () -> Void

    var body: some View {
        let s = stats.snapshot
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "GPU", trailing: MacStatsFormat.percent(s.gpu?.utilization), number: s.gpu?.utilization, back: back)
            Text("Last 10 minutes").font(.system(size: 13)).foregroundStyle(IsletInk.secondary)
            let points = stats.buckets
            LoadChart(layers: [(colour: MacStatsColour.gpu, values: points.map(\.gpu))], newest: points.last?.date)
                .padding(.top, 8)

            Rule()
            VStack(spacing: 7) {
                StatRow("Neural Engine", s.energy.map { $0.neuralEngine < 0.05 ? "Idle" : MacStatsFormat.watts($0.neuralEngine) } ?? "–")
                StatRow("Memory in use", s.gpu.map { MacStatsFormat.megabytes($0.memoryInUse) } ?? "–",
                        number: s.gpu.map { Double($0.memoryInUse) })
                StatRow("Power", MacStatsFormat.watts(s.energy?.gpu), number: s.energy?.gpu)
                StatRow("Temperature", MacStatsFormat.temperatures(s.thermal.gpuAverage, hottest: s.thermal.gpuHottest))
            }

            Rule()
            StatsSectionLabel("Using the most")
            ProcessList(groups: ProcessNames.group(s.topGPU, limit: 8), empty: "Nothing is using the GPU right now.",
                        format: MacStatsFormat.share, gap: 0.02)
            Caption("Only apps using the GPU right now.").padding(.top, 8)
            Rule()
            Footer()
        }
    }
}

// MARK: - Fans

private struct MacStatsFansPage: View {
    let stats: MacStats
    let back: () -> Void
    let fans = FanControl.shared
    /// The slider while it's being dragged; sent when it's let go.
    @State private var dragging: Double?
    /// The mode picker's selection slides between the modes.
    @Namespace private var picker

    var body: some View {
        let s = stats.snapshot
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Fans", trailing: nil, back: back) {
                if let t = s.thermal.cpuAverage {
                    Text("CPU \(MacStatsFormat.temperature(t))").font(.system(size: 13)).foregroundStyle(IsletInk.secondary)
                }
            }
            VStack(spacing: 10) {
                ForEach(Array(s.fans.enumerated()), id: \.offset) { i, fan in
                    VStack(spacing: 5) {
                        StatRow(MacStatsFormat.fanName(i, of: s.fans.count), MacStatsFormat.rpm(fan.rpm), number: fan.rpm)
                        MeterBar(fraction: fan.rpm / max(fan.max, 1), colour: Color(nsColor: .labelColor))
                    }
                }
            }

            Rule()
            if FanControl.isEnabled {
                // What's under the switch fades in and out with the mode, the takeover and any note, while the panel
                // eases to its new size, rather than popping in.
                control(s)
                    .animation(.easeInOut(duration: 0.2), value: modeIndex)
                    .animation(.easeInOut(duration: 0.2), value: fans.busy)
                    .animation(.easeInOut(duration: 0.2), value: fans.note)
                    .animation(.easeInOut(duration: 0.2), value: helperIndex)
            } else {
                StatRow("Control", s.fansHeld ? "Manual" : "Automatic")
                Caption(Self.automaticNote).padding(.top, 8)
            }
        }
        .onAppear { fans.refresh() }
    }

    static let automaticNote = "macOS runs the fans. On this Mac they stay off until it gets warm, then speed up as it heats."

    private var modeIndex: Int { switch fans.mode { case .automatic: 0; case .manual: 1; case .full: 2 } }

    private var helperIndex: Int {
        switch fans.helper { case .ready: 0; case .needsApproval: 1; case .notInstalled: 2; case .failed: 3 }
    }

    @ViewBuilder private func control(_ s: MacStatsSnapshot) -> some View {
        StatsSectionLabel("Control")
        switch fans.helper {
        case .ready:
            modePicker
            // Overlapping while one fades into the other, so the two never stack up for a moment.
            ZStack(alignment: .topLeading) {
                Group {
                    switch fans.mode {
                    case .automatic:
                        Caption(Self.automaticNote).padding(.top, 10)
                    case .manual(let rpm):
                        slider(rpm: rpm, range: range(s))
                    case .full:
                        Caption("Both fans at full speed, for cooling down fast. Loud.").padding(.top, 10)
                    }
                }
                .id(modeIndex)
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if fans.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Caption("Taking over the fans…")
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
            if let note = fans.note {
                Text(note).font(.system(size: 11)).foregroundStyle(Color.isletRedText).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            Rule()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield").font(.system(size: 11)).foregroundStyle(IsletInk.secondary)
                Caption("Back to Automatic when Dynamic Peninsula quits, the Mac sleeps or restarts, or the CPU reaches \(MacStatsFormat.temperature(FanHelperInfo.handBackCelsius)).")
            }
        case .needsApproval:
            Caption("Allow Dynamic Peninsula's fan helper in Login Items, under Allow in the Background.")
            Pill(title: "Open Login Items…", chevron: false) { fans.openLoginItems() }.padding(.top, 8)
        case .notInstalled, .failed:
            Caption("Changing the fans needs a small helper that runs as an administrator. macOS asks you to allow it once.")
            if case .failed(let why) = fans.helper {
                Text(why).font(.system(size: 11)).foregroundStyle(Color.isletRedText).padding(.top, 6)
            }
            Pill(title: "Install Fan Helper…", chevron: false) { fans.install() }.padding(.top, 8)
        }
    }

    /// Automatic / Manual / Full Speed, like the battery's Energy Mode switch.
    private var modePicker: some View {
        let current = modeIndex
        let items: [(String, String)] = [("Automatic", "gauge.with.dots.needle.33percent"), ("Manual", "slider.horizontal.3"),
                                         ("Full Speed", "fanblades.fill")]
        return HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let selected = i == current
                Button {
                    switch i {
                    case 0: fans.setAutomatic()
                    case 1: fans.setManual(rpm: manualStart)
                    default: fans.setFull()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.1).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? IsletInk.primary : IsletInk.tertiary)
                        Text(item.0).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selected ? IsletInk.primary : IsletInk.secondary)
                            .lineLimit(1).fixedSize()
                    }
                    .padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: 26)
                    .background {
                        if selected { IsletCard(shape: Capsule()).matchedGeometryEffect(id: "selection", in: picker) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(StatsPressStyle(shape: Capsule(), scales: false))
                // Automatic stays pressable while the fans are being taken over, to call it off.
                .disabled(fans.busy && i != 0)
            }
        }
        .padding(3)
        .background(Capsule().fill(IsletInk.faint))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: current)
    }

    /// Where Manual starts: the fans' speed now if they're turning, else a quiet 3,000 rpm.
    private var manualStart: Double {
        let r = range(stats.snapshot)
        let now = stats.snapshot.fastestFan?.rpm ?? 0
        return min(max(now > 1 ? (now / 100).rounded() * 100 : 3000, r.lowerBound), r.upperBound)
    }

    private func range(_ s: MacStatsSnapshot) -> ClosedRange<Double> {
        let lo = s.fans.map(\.min).max() ?? 2300, hi = s.fans.map(\.max).min() ?? 7800
        return lo < hi ? lo...hi : 2300...7800
    }

    private func slider(rpm: Double, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 6) {
            StatRow("Both fans", MacStatsFormat.rpm(dragging ?? rpm), number: dragging ?? rpm)
            Slider(value: Binding(get: { dragging ?? rpm }, set: { dragging = $0 }), in: range, step: 100) { editing in
                if !editing, let value = dragging {
                    dragging = nil
                    fans.setManual(rpm: value)
                }
            }
            .controlSize(.small)
            .disabled(fans.busy)
            HStack {
                Text("Quietest")
                Spacer()
                Text("Fastest")
            }
            .font(.system(size: 10)).foregroundStyle(IsletInk.tertiary)
            Caption("If the Mac gets too hot for this speed, macOS takes over again.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(.top, 12)
    }
}

// MARK: - Parts

private struct PageHeader<Trailing: View>: View {
    let title: String
    let trailing: String?
    let number: Double?
    let back: () -> Void
    @ViewBuilder var extra: Trailing

    init(title: String, trailing: String?, number: Double? = nil, back: @escaping () -> Void,
         @ViewBuilder extra: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
        self.number = number
        self.back = back
        self.extra = extra()
    }

    var body: some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(IsletCard(shape: Circle()))
                    Text(title).font(.system(size: 15, weight: .bold))
                }
                // Room round the name for the hover's pill.
                .padding(.trailing, 10)
                .foregroundStyle(IsletInk.primary)
                .contentShape(Capsule())
            }
            .buttonStyle(StatsPressStyle(shape: Capsule()))
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .help("Back")
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(IsletInk.primary)
                    .rolls(number)
            }
            extra
        }
        .padding(.bottom, 12)
    }
}

/// Load over the last 10 minutes, stacked when there's more than one series.
private struct LoadChart: View {
    /// Bottom to top.
    let layers: [(colour: Color, values: [Double])]
    let newest: Date?

    var body: some View {
        // Each layer sits on the ones under it.
        var stacked: [[Double]] = []
        for layer in layers {
            let below = stacked.last
            stacked.append(layer.values.enumerated().map { i, v in v + (below.map { i < $0.count ? $0[i] : 0 } ?? 0) })
        }
        let colours = layers.map(\.colour)
        return PercentFrame(height: 84) {
            SlidingPlot(series: stacked, newest: newest, top: 1) { drawn, top in
                ZStack {
                    ForEach(drawn.indices, id: \.self) { i in
                        SlotShape(kind: .area, upper: drawn[i], lower: i == 0 ? .zero : drawn[i - 1], top: top)
                            .fill(colours[min(i, colours.count - 1)])
                    }
                }
            }
        }
        .overlay {
            if (layers.first?.values.count ?? 0) < 2 {
                Text("Starting…").font(.system(size: 11)).foregroundStyle(IsletInk.tertiary)
            }
        }
    }
}

/// How full memory was over the last 10 minutes: a thin bar a slot, coloured by the pressure at the time.
private struct MemoryChart: View {
    let points: [MacStatsPoint]

    var body: some View {
        // One series a pressure level, each bar in the series of its own level and nothing in the others.
        let levels: [StatLevel] = [.normal, .warning, .critical]
        let series = levels.map { level in points.map { StatLevel($0.memoryPressure) == level ? $0.memoryFraction : 0 } }
        let colours = levels.map { MacStatsColour.level($0) ?? MacStatsColour.memory }
        return PercentFrame(height: 64) {
            SlidingPlot(series: series, newest: points.last?.date, top: 1) { drawn, top in
                ZStack {
                    ForEach(drawn.indices, id: \.self) { i in
                        SlotShape(kind: .bars, upper: drawn[i], lower: .zero, top: top).fill(colours[i])
                    }
                }
            }
        }
    }
}

/// A plot with 0, 50 and 100% marked across it and labelled on the right; no time labels.
private struct PercentFrame<Plot: View>: View {
    let height: CGFloat
    @ViewBuilder let plot: Plot

    var body: some View {
        HStack(spacing: 5) {
            plot
                .background {
                    GeometryReader { g in
                        Path { p in
                            for f in [0.0, 0.5, 1.0] {
                                let y = min(max((g.size.height * (1 - f)).rounded() + 0.5, 0.5), g.size.height - 0.5)
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: g.size.width, y: y))
                            }
                        }
                        .stroke(IsletInk.rule, lineWidth: 1)
                    }
                }
            ZStack(alignment: .topLeading) {
                ForEach([0.0, 0.5, 1.0], id: \.self) { f in
                    Text("\(Int(f * 100))%").font(.system(size: 9)).foregroundStyle(IsletInk.tertiary)
                        .fixedSize()
                        .position(x: 12, y: min(max(height * (1 - f), 5), height - 5))
                }
            }
            .frame(width: 24, height: height)
        }
        .frame(height: height)
    }
}

private struct Sparkline: View {
    let values: [Double]
    /// The newest slot's start: a new one slides the line along; the same one only updates its value.
    let newest: Date?
    let top: Double
    /// nil: the label colour.
    let colour: Color?

    var body: some View {
        let ink = colour ?? Color(nsColor: .labelColor)
        SlidingPlot(series: [values], newest: newest, top: top) { drawn, top in
            if let line = drawn.first, line.values.count > 1 {
                ZStack {
                    SlotShape(kind: .area, upper: line, lower: .zero, top: top, inset: 0.75).fill(ink.opacity(0.18))
                    SlotShape(kind: .line, upper: line, lower: .zero, top: top, inset: 0.75)
                        .stroke(ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 26)
        .padding(.top, 6)
    }
}

/// The 10 minutes in slots, the newest at the right edge (DESIGN.md "Mac Stats (1.7)", Motion), for the sparklines
/// and the pages' charts alike. Within a slot, a new reading eases the newest point (and the scale) to its value; a
/// new slot slides everything along a step, so the plot never jumps.
private struct SlidingPlot<Content: View>: View {
    let series: [[Double]]
    let newest: Date?
    let top: Double
    @ViewBuilder let content: (_ drawn: [SlotValues], _ top: Double) -> Content

    /// What's drawn: set together with `shift`, so a new slot never shows a frame out of place. Empty until the
    /// first showing, which draws `series` as it is.
    @State private var drawn: [SlotValues] = []
    @State private var drawnTop: Double = 1
    /// 1 when a slot has just started, the plot one step right of where it belongs; it eases to 0 to slide along.
    @State private var shift: CGFloat = 0
    @State private var slot: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let step = geo.size.width / CGFloat(SlotShape.slots - 1)
            let started = !drawn.isEmpty
            content(started ? drawn : series.map(SlotValues.init), started ? drawnTop : top)
                .offset(x: shift * step)
        }
        .clipped()
        .onAppear {
            drawn = series.map(SlotValues.init)
            drawnTop = top
            slot = newest
        }
        .onChange(of: series) { _, now in update(now) }
    }

    private func update(_ now: [[Double]]) {
        let values = now.map(SlotValues.init)
        let motion = reduceMotion ? nil : MacStatsMotion.reading
        guard newest != slot, !drawn.isEmpty else {
            // The same slot: the newest point and the scale ease to the reading.
            withAnimation(motion) {
                drawn = values
                drawnTop = top
            }
            slot = newest
            return
        }
        slot = newest
        // A new slot: drawn one step right, where the old points already are, then slid into place.
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            drawn = values
            shift = 1
        }
        withAnimation(motion) {
            shift = 0
            drawnTop = top
        }
    }
}

/// A series' values in a form SwiftUI can animate between, so a plot's points ease to their new heights.
struct SlotValues: VectorArithmetic {
    var values: [Double]

    static var zero: SlotValues { SlotValues(values: []) }
    static func + (a: SlotValues, b: SlotValues) -> SlotValues { combine(a, b, +) }
    static func - (a: SlotValues, b: SlotValues) -> SlotValues { combine(a, b, -) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }

    /// Element by element; a shorter one counts as 0 past its end (only `zero`: the plots never animate between
    /// different lengths, a new slot is drawn without animation).
    private static func combine(_ a: SlotValues, _ b: SlotValues, _ f: (Double, Double) -> Double) -> SlotValues {
        let n = max(a.values.count, b.values.count)
        return SlotValues(values: (0..<n).map { i in
            f(i < a.values.count ? a.values[i] : 0, i < b.values.count ? b.values[i] : 0)
        })
    }
}

/// One series across the plot, one slot a step, the newest at the right edge.
private struct SlotShape: Shape {
    enum Kind { case area, line, bars }
    static let slots = 120
    static let barWidth: CGFloat = 1.2

    var kind: Kind
    /// Only the newest point of each series, and the scale, are animated: within a slot nothing else changes, and
    /// easing all 120 points every frame (new arrays each time) was the panel's biggest drawing cost. A new slot is
    /// drawn without animation, so the older points never need to ease.
    private var upperHead: [Double]
    private var upperTip: Double
    private var upperCount: Int
    private var lowerHead: [Double]
    private var lowerTip: Double
    private var lowerCount: Int
    /// The value at the top edge.
    var top: Double
    /// Room kept at the top and bottom, for a stroke's width.
    var inset: CGFloat = 0

    /// `lower`: what an area sits on (a stacked chart's layer below); `zero` for the baseline.
    init(kind: Kind, upper: SlotValues, lower: SlotValues, top: Double, inset: CGFloat = 0) {
        self.kind = kind
        let up = upper.values.suffix(Self.slots), lo = lower.values.suffix(Self.slots)
        upperHead = Array(up.dropLast())
        upperTip = up.last ?? 0
        upperCount = up.count
        lowerHead = Array(lo.dropLast())
        lowerTip = lo.last ?? 0
        lowerCount = lo.count
        self.top = top
        self.inset = inset
    }

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(upperTip, lowerTip), top) }
        set {
            upperTip = newValue.first.first
            lowerTip = newValue.first.second
            top = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let n = upperCount
        guard n > 0, top > 0 else { return Path() }
        func up(_ i: Int) -> Double { i < n - 1 ? upperHead[i] : upperTip }
        let r = rect.insetBy(dx: 0, dy: inset)
        let step = rect.width / CGFloat(Self.slots - 1)
        func x(_ i: Int) -> CGFloat { rect.maxX - CGFloat(n - 1 - i) * step }
        func y(_ v: Double) -> CGFloat { r.maxY - CGFloat(min(max(v / top, 0), 1)) * r.height }
        // The lower series ends at the same newest slot, and may be the shorter.
        let m = min(lowerCount, n)
        func below(_ i: Int) -> Double {
            guard m > 0 else { return 0 }
            let e = lowerCount - m + max(0, i - (n - m))
            return e < lowerCount - 1 ? lowerHead[e] : lowerTip
        }

        var p = Path()
        switch kind {
        case .line:
            guard n > 1 else { return p }
            p.addLines((0..<n).map { CGPoint(x: x($0), y: y(up($0))) })
        case .area:
            guard n > 1 else { return p }
            p.move(to: CGPoint(x: x(0), y: y(below(0))))
            for i in 0..<n { p.addLine(to: CGPoint(x: x(i), y: y(up(i)))) }
            for i in (0..<n).reversed() { p.addLine(to: CGPoint(x: x(i), y: y(below(i)))) }
            p.closeSubpath()
        case .bars:
            for i in 0..<n where up(i) > 0 {
                let h = r.maxY - y(up(i))
                p.addRect(CGRect(x: x(i) - Self.barWidth, y: r.maxY - h, width: Self.barWidth, height: h))
            }
        }
        return p
    }
}

private struct MeterBar: View {
    let fraction: Double
    let colour: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height, w = geo.size.width * min(max(fraction, 0), 1)
            Capsule().fill(IsletInk.faint)
                .overlay(alignment: .leading) {
                    // Never narrower than it is tall, slid back under the track's rounded end instead: a small load
                    // shows as a sliver of the bar's round end, not a squashed oval.
                    Capsule().fill(colour).frame(width: max(w, h)).offset(x: min(w - h, 0))
                        .opacity(w > 0 ? 1 : 0)
                }
                .clipShape(Capsule())
        }
        .frame(height: 5)
        .readingMotion(fraction)
    }
}

private struct VBar: View {
    let fraction: Double
    let colour: Color

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(IsletInk.faint)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(colour).frame(height: geo.size.height * min(max(fraction, 0), 1))
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .readingMotion(fraction)
    }
}

private struct ProcessList: View {
    let groups: [ProcessGroup]
    let empty: String
    let format: (Double) -> String
    /// How much more a row must use to pass the one above it (`ProcessOrder`).
    let gap: Double
    /// Hovering a row offers to quit it (the CPU and Memory pages).
    var stoppable = false

    /// Every row the same height and room for all five, so a row with a second line or a sixth app never changes
    /// the page's height (which moved the whole panel).
    static let rows = 5
    static let rowHeight: CGFloat = 30
    static let spacing: CGFloat = 4

    /// The order shown last, so rows only change places for a clear difference (`ProcessOrder`).
    @State private var order: [String] = []

    var body: some View {
        let ranked = ProcessOrder.steady(groups, after: order, gap: gap)
        Group {
            if groups.isEmpty {
                Text(empty).font(.system(size: 12)).foregroundStyle(IsletInk.tertiary)
            } else {
                VStack(spacing: Self.spacing) {
                    ForEach(ranked.prefix(Self.rows)) { g in
                        ProcessRow(group: g, value: format(g.value), stoppable: stoppable && ProcessStopper.canStop(g))
                            .frame(height: Self.rowHeight)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: CGFloat(Self.rows) * Self.rowHeight + CGFloat(Self.rows - 1) * Self.spacing, alignment: .top)
        .onChange(of: ranked.map(\.id), initial: true) { _, ids in order = ids }
    }
}

/// Keeps the "Using the most" lists steady: two apps using about the same swapped places on nearly every reading,
/// and the rows kept sliding past each other. A row now only passes the one above it when it uses clearly more.
enum ProcessOrder {
    /// `previous`: the ids in the order last shown. `gap`: how much more, besides a tenth more, a row needs to pass
    /// the one above (in the list's own unit).
    static func steady(_ groups: [ProcessGroup], after previous: [String], gap: Double) -> [ProcessGroup] {
        let rank = Dictionary(previous.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        // The last order first, newcomers after it, biggest first.
        var list = groups.sorted { a, b in
            switch (rank[a.id], rank[b.id]) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.value > b.value
            }
        }
        // Then each row moves up past every row it clearly beats.
        for i in list.indices.dropFirst() {
            var j = i
            while j > 0, list[j].value > list[j - 1].value * 1.1 + gap {
                list.swapAt(j, j - 1)
                j -= 1
            }
        }
        return list
    }
}

private struct ProcessRow: View {
    let group: ProcessGroup
    let value: String
    let stoppable: Bool
    private let stopper = ProcessStopper.shared
    @State private var hovering = false

    var body: some View {
        let g = group
        let state = stopper.state(g)
        HStack(spacing: 8) {
            ProcessIcon(group: g).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(g.name).font(.system(size: 13)).foregroundStyle(IsletInk.primary).lineLimit(1)
                if let detail = g.detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(IsletInk.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            switch state {
            case .quitting:
                Text("Quitting…").font(.system(size: 12)).foregroundStyle(IsletInk.tertiary)
                    .transition(.opacity)
            case .stubborn:
                Button { stopper.forceQuit(g) } label: {
                    Text("Force Quit").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 9).frame(height: 20)
                        .background(Capsule().fill(Color.isletRed))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(g.name) didn't quit. Force Quit loses anything unsaved.")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            case nil:
                if stoppable && hovering {
                    Button { stopper.quit(g) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                            .foregroundStyle(IsletInk.secondary)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Quit \(g.name)")
                    .accessibilityLabel("Quit \(g.name)")
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
                Text(value).font(.system(size: 13)).monospacedDigit().foregroundStyle(IsletInk.primary)
                    .rolls(g.value)
            }
        }
        .contentShape(Rectangle())
        .onHover { over in withAnimation(.easeOut(duration: 0.15)) { hovering = over } }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state)
        .help(g.members.count > 1 ? g.members.joined(separator: ", ") : g.detail ?? g.members.first ?? g.name)
    }
}

private struct ProcessIcon: View {
    let group: ProcessGroup
    var body: some View { icon(group) }

    @ViewBuilder private func icon(_ g: ProcessGroup) -> some View {
        if let app = g.appPath {
            Image(nsImage: ProcessNames.icon(app)).resizable().interpolation(.high)
        } else {
            // macOS's own processes and anything else without an app.
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(IsletInk.faint)
                .overlay(Image(systemName: g.detail != nil ? "gearshape.fill" : "terminal.fill")
                    .font(.system(size: 9)).foregroundStyle(IsletInk.secondary))
                .padding(1)
        }
    }
}

private struct Footer: View {
    var body: some View {
        HStack {
            Text("Updated every \(MacStatsSettings.intervalSeconds) s").font(.system(size: 11)).foregroundStyle(IsletInk.tertiary)
            Spacer()
            Pill(title: "Activity Monitor…", chevron: false) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                                   configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
}

private struct Pill: View {
    let title: String
    let chevron: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .semibold))
                if chevron { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)) }
            }
            .foregroundStyle(IsletInk.primary)
            .padding(.horizontal, 10).frame(height: 22)
            .background(IsletCard(shape: Capsule()))
            .contentShape(Capsule())
        }
        .buttonStyle(StatsPressStyle(shape: Capsule()))
    }
}

private struct Rule: View {
    var body: some View { Rectangle().fill(IsletInk.rule).frame(height: 1).padding(.vertical, 12) }
}

private struct StatsSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 13)).foregroundStyle(IsletInk.secondary).padding(.bottom, 8) }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(IsletInk.tertiary).fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var colour: Color?
    /// What `value` shows, when it's one number, so its digits roll the right way.
    var number: Double?
    init(_ label: String, _ value: String, colour: Color? = nil, number: Double? = nil) {
        self.label = label
        self.value = value
        self.colour = colour
        self.number = number
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(IsletInk.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().lineLimit(1)
                .foregroundStyle(colour.map { AnyShapeStyle($0) } ?? AnyShapeStyle(IsletInk.primary))
                .rolls(number)
        }
        .font(.system(size: 13))
    }
}

private struct KeyRow: View {
    let label: String
    let value: String
    let key: Color?
    let number: Double
    init(_ label: String, _ value: String, _ key: Color?, number: Double) {
        self.label = label
        self.value = value
        self.key = key
        self.number = number
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(key ?? .clear).frame(width: 8, height: 8)
            Text(label).foregroundStyle(IsletInk.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().foregroundStyle(IsletInk.primary)
                .rolls(number)
        }
        .font(.system(size: 13))
    }
}

private struct Legend: View {
    let name: String
    let colour: Color
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(colour).frame(width: 7, height: 7)
            Text(name).font(.system(size: 10)).foregroundStyle(IsletInk.secondary).fixedSize()
        }
        .padding(.leading, 6)
    }
}

// MARK: - Charts

/// The history in 5-second slots (120 over the 10 minutes), averaged: at one reading a second the charts would
/// otherwise redraw 600 marks a series every second while the panel is open.
enum ChartHistory {
    static let slot: TimeInterval = 5

    static func buckets(_ history: [MacStatsPoint]) -> [MacStatsPoint] {
        var out: [MacStatsPoint] = []
        var run: [MacStatsPoint] = []
        func flush() {
            guard var p = run.first else { return }
            let n = Double(run.count)
            p.date = Date(timeIntervalSinceReferenceDate: (run[0].date.timeIntervalSinceReferenceDate / slot).rounded(.down) * slot)
            p.efficiency = run.map(\.efficiency).reduce(0, +) / n
            p.performance = run.map(\.performance).reduce(0, +) / n
            p.user = run.map(\.user).reduce(0, +) / n
            p.system = run.map(\.system).reduce(0, +) / n
            p.gpu = run.map(\.gpu).reduce(0, +) / n
            p.memoryFraction = run.map(\.memoryFraction).reduce(0, +) / n
            p.memoryPressure = run.last!.memoryPressure
            let watts = run.compactMap(\.watts)
            p.watts = watts.isEmpty ? nil : watts.reduce(0, +) / Double(watts.count)
            out.append(p)
            run = []
        }
        for p in history {
            if let first = run.first,
               (p.date.timeIntervalSinceReferenceDate / slot).rounded(.down) != (first.date.timeIntervalSinceReferenceDate / slot).rounded(.down) {
                flush()
            }
            run.append(p)
        }
        flush()
        return out
    }
}

// MARK: - Motion

/// The panel's motion (DESIGN.md "Mac Stats (1.7)", Motion): the battery stats' spring for each reading.
enum MacStatsMotion {
    static let reading = Animation.spring(response: 0.7, dampingFraction: 0.9)
    /// A page fading in: the same curve and length as the panel easing to its size (`MenuBarPanel.settle`).
    static let settle = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
}

private struct ReadingMotion<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : MacStatsMotion.reading, value: value)
    }
}

private extension View {
    /// Eases to each reading on the panel's spring; not with Reduce Motion.
    func readingMotion<Value: Equatable>(_ value: Value) -> some View { modifier(ReadingMotion(value: value)) }

    /// Digits roll up as `value` rises and down as it falls; text that isn't one number just rolls.
    @ViewBuilder func rolls(_ value: Double?) -> some View {
        if let value { contentTransition(.numericText(value: value)) } else { contentTransition(.numericText()) }
    }
}

/// The tiles', pills' and back button's feedback: a faint veil while the pointer is over it, a little press.
private struct StatsPressStyle<S: Shape>: ButtonStyle {
    let shape: S
    /// Whether a press shrinks it a little (not the mode switch's segments, which sit in a track).
    var scales = true

    func makeBody(configuration: Configuration) -> some View {
        StatsPressBody(configuration: configuration, shape: shape, scales: scales)
    }
}

private struct StatsPressBody<S: Shape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    let scales: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .overlay {
                shape.fill(IsletInk.primary.opacity(pressed ? 0.1 : hovering && enabled ? 0.05 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(pressed && scales && !reduceMotion ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: pressed)
            .onHover { over in withAnimation(.easeOut(duration: 0.15)) { hovering = over } }
    }
}

// MARK: - Colours and wording

enum MacStatsColour {
    static let efficiency = Color(nsColor: MacStatsMenuBar.colour(.efficiency))
    static let performance = Color(nsColor: MacStatsMenuBar.colour(.performance))
    static let gpu = Color(nsColor: MacStatsMenuBar.colour(.gpu))
    static let memory = Color(nsColor: MacStatsMenuBar.colour(.memory))

    /// Yellow or red, or nil for the usual colour; nothing while "Warn in yellow and red" is off.
    static func level(_ level: StatLevel) -> Color? {
        guard MacStatsSettings.on(MacStatsSettings.warnings) else { return nil }
        return MacStatsMenuBar.colour(level).map { Color(nsColor: $0) }
    }
}

enum MacStatsFormat {
    static func percent(_ x: Double?) -> String { x.map { "\(Int(($0 * 100).rounded()))%" } ?? "–" }

    /// A process's share of a core or the GPU: "59.5%".
    static func share(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

    static func number(_ x: Double) -> String { String(format: "%.1f", x) }

    static func watts(_ w: Double?) -> String { w.map { String(format: "%.1f W", $0) } ?? "–" }

    static func gigabytes(_ bytes: UInt64, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f GB", Double(bytes) / 1_073_741_824)
    }

    static func megabytes(_ bytes: UInt64) -> String { "\(Int((Double(bytes) / 1_048_576).rounded())) MB" }

    /// "679 MB", or "1.86 GB" from a gigabyte up.
    static func megabytesOrGigabytes(_ bytes: Double) -> String {
        bytes >= 1_073_741_824 ? String(format: "%.2f GB", bytes / 1_073_741_824) : "\(Int((bytes / 1_048_576).rounded())) MB"
    }

    static func rpm(_ rpm: Double) -> String {
        rpm < 1 ? "Off" : "\(Int(rpm.rounded()).formatted(.number.grouping(.automatic))) rpm"
    }

    static func pressure(_ p: MemoryPressure) -> String {
        switch p {
        case .normal: "normal"
        case .warning: "high"
        case .critical: "critical"
        }
    }

    /// "Left" and "Right" for a MacBook Pro's two fans; numbered otherwise.
    static func fanName(_ i: Int, of count: Int) -> String {
        count == 2 ? (i == 0 ? "Left" : "Right") : count == 1 ? "Fan" : "Fan \(i + 1)"
    }

    /// Whole degrees, in the region's units (°F in the US).
    static func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 0
        return f.string(from: Measurement(value: celsius, unit: UnitTemperature.celsius))
    }

    static func temperatures(_ average: Double?, hottest: Double?) -> String {
        guard average != nil else { return "–" }
        return temperature(average) + (hottest.map { " · hottest \(temperature($0))" } ?? "")
    }

    /// "Up 6 days, 10 hr".
    static func uptime(now: Date = Date()) -> String? {
        guard let boot = MacStats.bootDate else { return nil }
        let f = DateComponentsFormatter()
        f.allowedUnits = now.timeIntervalSince(boot) >= 86_400 ? [.day, .hour] : [.hour, .minute]
        f.unitsStyle = .short
        f.maximumUnitCount = 2
        return f.string(from: boot, to: now).map { "Up \($0)" }
    }
}
