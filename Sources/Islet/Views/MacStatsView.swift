import Charts
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch state.page {
            case .overview:
                MacStatsOverview(stats: stats, open: { state.page = $0 })
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .cpu: page { MacStatsCPUPage(stats: stats, back: back) }
            case .memory: page { MacStatsMemoryPage(stats: stats, back: back) }
            case .gpu: page { MacStatsGPUPage(stats: stats, back: back) }
            case .fans: page { MacStatsFansPage(stats: stats, back: back) }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: state.page)
        .onChange(of: state.page, initial: true) { _, page in
            stats.wantsProcesses = [.cpu, .memory, .gpu].contains(page)
        }
    }

    private func back() { state.page = .overview }

    private func page(@ViewBuilder _ content: () -> some View) -> some View {
        content().transition(.move(edge: .trailing).combined(with: .opacity))
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
                    Tile(title: "CPU", value: MacStatsFormat.percent(s.cpu?.total),
                         level: StatLevel(load: max(s.cpu?.efficiency ?? 0, s.cpu?.performance ?? 0)), action: { open(.cpu) }) {
                        VStack(spacing: 6) {
                            CoreTypeRow(letter: "E", value: s.cpu?.efficiency, colour: MacStatsColour.efficiency)
                            CoreTypeRow(letter: "P", value: s.cpu?.performance, colour: MacStatsColour.performance)
                        }
                        .padding(.top, 6)
                    }
                    Tile(title: "GPU", value: MacStatsFormat.percent(s.gpu?.utilization),
                         level: StatLevel(load: s.gpu?.utilization ?? 0), action: { open(.gpu) }) {
                        Caption(s.gpu.map { "\(MacStatsFormat.megabytes($0.memoryInUse)) in use" } ?? " ")
                        Sparkline(values: stats.history.map(\.gpu), top: 1, colour: MacStatsColour.gpu)
                    }
                }
                GridRow {
                    Tile(title: "Memory", value: MacStatsFormat.percent(s.memory?.fraction),
                         level: StatLevel(s.memory?.pressure ?? .normal), action: { open(.memory) }) {
                        Caption(s.memory.map { "\(MacStatsFormat.gigabytes($0.used)) of \(MacStatsFormat.gigabytes($0.total, decimals: 0))" } ?? " ")
                        if let m = s.memory { MemoryBar(memory: m, height: 6).padding(.top, 8) }
                        Text("Pressure \(MacStatsFormat.pressure(s.memory?.pressure ?? .normal))")
                            .font(.system(size: 11))
                            .foregroundStyle(MacStatsColour.level(StatLevel(s.memory?.pressure ?? .normal)) ?? Color(nsColor: .tertiaryLabelColor))
                            .padding(.top, 6)
                    }
                    Tile(title: "Power", value: MacStatsFormat.watts(s.systemWatts), level: .normal, action: nil) {
                        Caption(s.energy.map { "CPU \(MacStatsFormat.number($0.cpu)) · GPU \(MacStatsFormat.number($0.gpu)) W" } ?? " ")
                        let watts = stats.history.compactMap(\.watts)
                        Sparkline(values: watts, top: max(watts.max() ?? 1, 1) * 1.15, colour: nil)
                    }
                }
            }

            Rule()
            StatsSectionLabel("Temperature")
            VStack(spacing: 7) {
                StatRow("CPU", MacStatsFormat.temperature(s.thermal.cpuAverage),
                        colour: s.thermal.cpuAverage.flatMap { MacStatsColour.level(StatLevel(celsius: $0)) })
                StatRow("GPU", MacStatsFormat.temperature(s.thermal.gpuAverage),
                        colour: s.thermal.gpuAverage.flatMap { MacStatsColour.level(StatLevel(celsius: $0)) })
                if s.thermal.ssd != nil { StatRow("SSD", MacStatsFormat.temperature(s.thermal.ssd)) }
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
                        StatRow(MacStatsFormat.fanName(i, of: s.fans.count), MacStatsFormat.rpm(fan.rpm))
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
    let level: StatLevel
    let action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        let body = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(IsletInk.secondary)
                if action != nil {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(IsletInk.tertiary)
                }
            }
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(MacStatsColour.level(level) ?? Color(nsColor: .labelColor))
                .contentTransition(.numericText())
            content
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(IsletCard(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        if let action {
            Button(action: action) { body }.buttonStyle(.plain)
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
            PageHeader(title: "CPU", trailing: MacStatsFormat.percent(s.cpu?.total), back: back)
            HStack(spacing: 0) {
                Text("Last 10 minutes").font(.system(size: 13)).foregroundStyle(IsletInk.secondary).fixedSize()
                Spacer(minLength: 4)
                if eCount > 0 { Legend(name: "Efficiency", colour: MacStatsColour.efficiency) }
                Legend(name: "Performance", colour: MacStatsColour.performance)
            }
            LoadChart(points: stats.history.flatMap { p -> [LoadChart.Point] in
                let e = p.efficiency * Double(eCount) / Double(cores)
                let perf = p.performance * Double(cores - eCount) / Double(cores)
                return (eCount > 0 ? [LoadChart.Point(date: p.date, series: "Efficiency", value: e)] : [])
                    + [LoadChart.Point(date: p.date, series: "Performance", value: perf)]
            }, colours: ["Efficiency": MacStatsColour.efficiency, "Performance": MacStatsColour.performance])
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
            ProcessList(groups: ProcessNames.group(s.topCPU), empty: "Reading…", format: MacStatsFormat.share)
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
                       back: back)
            HStack {
                Text("Last 10 minutes").font(.system(size: 13)).foregroundStyle(IsletInk.secondary)
                Spacer()
                Text(MacStatsFormat.pressure(s.memory?.pressure ?? .normal).capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacStatsColour.level(StatLevel(s.memory?.pressure ?? .normal)) ?? Color(nsColor: .labelColor))
            }
            Chart {
                ForEach(Array(stats.history.enumerated()), id: \.offset) { _, p in
                    BarMark(x: .value("Time", p.date), y: .value("Used", p.memoryFraction), width: .fixed(1.2))
                        .foregroundStyle(MacStatsColour.level(StatLevel(p.memoryPressure)) ?? MacStatsColour.memory)
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-MacStats.historySpan)...Date())
            .percentAxes()
            .frame(height: 64)
            .padding(.top, 8)
            Caption("Full is fine: macOS keeps spare memory busy. The colour is pressure, how hard it's working to find room.")
                .padding(.top, 8)

            Rule()
            if let m = s.memory {
                MemoryBar(memory: m, height: 8)
                VStack(spacing: 7) {
                    KeyRow("Apps", MacStatsFormat.gigabytes(m.app), MacStatsColour.memory)
                    KeyRow("Kept for macOS", MacStatsFormat.gigabytes(m.wired), MacStatsColour.memory.opacity(0.6))
                    KeyRow("Compressed", MacStatsFormat.gigabytes(m.compressed), MacStatsColour.memory.opacity(0.35))
                    KeyRow("Free", MacStatsFormat.gigabytes(m.free), Color(nsColor: .quaternaryLabelColor))
                    KeyRow("Swap used", MacStatsFormat.megabytesOrGigabytes(Double(m.swapUsed)), nil)
                }
                .padding(.top, 10)
            }

            Rule()
            StatsSectionLabel("Using the most")
            ProcessList(groups: ProcessNames.group(s.topMemory), empty: "Reading…", format: MacStatsFormat.megabytesOrGigabytes)
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
            PageHeader(title: "GPU", trailing: MacStatsFormat.percent(s.gpu?.utilization), back: back)
            Text("Last 10 minutes").font(.system(size: 13)).foregroundStyle(IsletInk.secondary)
            LoadChart(points: stats.history.map { LoadChart.Point(date: $0.date, series: "GPU", value: $0.gpu) },
                      colours: ["GPU": MacStatsColour.gpu])
                .padding(.top, 8)

            Rule()
            VStack(spacing: 7) {
                StatRow("Neural Engine", s.energy.map { $0.neuralEngine < 0.05 ? "Idle" : MacStatsFormat.watts($0.neuralEngine) } ?? "–")
                StatRow("Memory in use", s.gpu.map { MacStatsFormat.megabytes($0.memoryInUse) } ?? "–")
                StatRow("Power", MacStatsFormat.watts(s.energy?.gpu))
                StatRow("Temperature", MacStatsFormat.temperatures(s.thermal.gpuAverage, hottest: s.thermal.gpuHottest))
            }

            Rule()
            StatsSectionLabel("Using the most")
            ProcessList(groups: ProcessNames.group(s.topGPU), empty: "Nothing is using the GPU right now.",
                        format: MacStatsFormat.share)
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
                        StatRow(MacStatsFormat.fanName(i, of: s.fans.count), MacStatsFormat.rpm(fan.rpm))
                        MeterBar(fraction: fan.rpm / max(fan.max, 1), colour: Color(nsColor: .labelColor))
                    }
                }
            }
            .animation(.easeOut(duration: 0.5), value: s.fans)

            Rule()
            StatRow("Control", s.fansHeld ? "Manual" : "Automatic")
            Caption("macOS runs the fans. On this Mac they stay off until it gets warm, then speed up as it heats.")
                .padding(.top, 8)
        }
    }
}

// MARK: - Parts

private struct PageHeader<Trailing: View>: View {
    let title: String
    let trailing: String?
    let back: () -> Void
    @ViewBuilder var extra: Trailing

    init(title: String, trailing: String?, back: @escaping () -> Void, @ViewBuilder extra: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
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
                .foregroundStyle(IsletInk.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .help("Back")
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(IsletInk.primary)
                    .contentTransition(.numericText())
            }
            extra
        }
        .padding(.bottom, 12)
    }
}

/// Load over the last 10 minutes, stacked when there's more than one series.
private struct LoadChart: View {
    struct Point { var date: Date; var series: String; var value: Double }
    let points: [Point]
    let colours: [String: Color]

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Time", p.date), y: .value("Load", p.value), stacking: .standard)
                    .foregroundStyle(by: .value("Series", p.series))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale(domain: Array(colours.keys).sorted(), range: Array(colours.keys).sorted().map { colours[$0]! })
        .chartLegend(.hidden)
        .chartXScale(domain: Date().addingTimeInterval(-MacStats.historySpan)...Date())
        .percentAxes()
        .frame(height: 84)
        .overlay {
            if points.count < 2 {
                Text("Starting…").font(.system(size: 11)).foregroundStyle(IsletInk.tertiary)
            }
        }
    }
}

private extension View {
    /// 0, 50 and 100% on the right; no time labels.
    func percentAxes() -> some View {
        chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 0.5, 1]) { v in
                    AxisGridLine().foregroundStyle(IsletInk.rule)
                    AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) * 100))%").font(.system(size: 9)).foregroundStyle(IsletInk.tertiary) }
                }
            }
            .chartXAxis(.hidden)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let top: Double
    /// nil: the label colour.
    let colour: Color?

    var body: some View {
        let ink = colour ?? Color(nsColor: .labelColor)
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    }
                    .fill(ink.opacity(0.18))
                    Path { p in p.addLines(pts) }
                        .stroke(ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 26)
        .padding(.top, 6)
    }

    /// The last 10 minutes across the width, newest at the right.
    private func points(in size: CGSize) -> [CGPoint] {
        let recent = values.suffix(120)
        guard recent.count > 1, top > 0 else { return [] }
        let step = size.width / CGFloat(recent.count - 1)
        return recent.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(min(max(v / top, 0), 1)) * (size.height - 1.5) - 0.75)
        }
    }
}

private struct MeterBar: View {
    let fraction: Double
    let colour: Color

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(IsletInk.faint)
                .overlay(alignment: .leading) {
                    Capsule().fill(colour).frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.4), value: fraction)
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
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

private struct ProcessList: View {
    let groups: [ProcessGroup]
    let empty: String
    let format: (Double) -> String

    var body: some View {
        if groups.isEmpty {
            Text(empty).font(.system(size: 12)).foregroundStyle(IsletInk.tertiary)
        } else {
            VStack(spacing: 7) {
                ForEach(groups) { g in
                    HStack(spacing: 8) {
                        icon(g).frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(g.name).font(.system(size: 13)).foregroundStyle(IsletInk.primary).lineLimit(1)
                            if let detail = g.detail {
                                Text(detail).font(.system(size: 10)).foregroundStyle(IsletInk.tertiary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(format(g.value)).font(.system(size: 13)).monospacedDigit().foregroundStyle(IsletInk.primary)
                    }
                    .help(g.members.count > 1 ? g.members.joined(separator: ", ") : g.detail ?? g.members.first ?? g.name)
                }
            }
        }
    }

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
        .buttonStyle(.plain)
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
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var colour: Color?
    init(_ label: String, _ value: String, colour: Color? = nil) {
        self.label = label
        self.value = value
        self.colour = colour
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(IsletInk.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().lineLimit(1)
                .foregroundStyle(colour.map { AnyShapeStyle($0) } ?? AnyShapeStyle(IsletInk.primary))
        }
        .font(.system(size: 13))
    }
}

private struct KeyRow: View {
    let label: String
    let value: String
    let key: Color?
    init(_ label: String, _ value: String, _ key: Color?) {
        self.label = label
        self.value = value
        self.key = key
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(key ?? .clear).frame(width: 8, height: 8)
            Text(label).foregroundStyle(IsletInk.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().foregroundStyle(IsletInk.primary)
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
