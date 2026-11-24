import SwiftUI
import XCTest
@testable import Islet

/// Renders the Mac Stats panel's pages from live readings to PNGs, to look at the layout without opening the panel.
/// Only runs when asked: `TEST_RUNNER_MACSTATS_RENDER_DIR=/some/folder xcodebuild test -only-testing:IsletTests/MacStatsPanelRenderTests`.
@MainActor
final class MacStatsPanelRenderTests: XCTestCase {
    func testRenderPages() async throws {
        guard let dir = ProcessInfo.processInfo.environment["MACSTATS_RENDER_DIR"] else { throw XCTSkip("Set MACSTATS_RENDER_DIR to render") }
        let stats = MacStats.shared
        stats.interval = .seconds(1)
        stats.start()
        stats.wantsProcesses = true
        try await Task.sleep(for: .seconds(6))
        for (name, page) in [("overview", MacStatsPage.overview), ("cpu", .cpu), ("memory", .memory), ("gpu", .gpu), ("fans", .fans)] {
            let state = MacStatsPanelState()
            state.page = page
            let view = MacStatsView(stats: stats, state: state)
                .background(Color(white: 0.13))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        stats.stop()
    }

    /// Settings > Mac Stats, drawn in an offscreen window (a grouped Form is AppKit underneath).
    func testRenderSettingsPage() throws {
        guard let dir = ProcessInfo.processInfo.environment["MACSTATS_RENDER_DIR"] else { throw XCTSkip("Set MACSTATS_RENDER_DIR to render") }
        let d = UserDefaults.standard
        let was = d.object(forKey: MacStatsSettings.enabled)
        d.set(true, forKey: MacStatsSettings.enabled)
        defer { d.set(was, forKey: MacStatsSettings.enabled) }
        let host = NSHostingView(rootView: MacStatsSettingsPage().frame(width: 520, height: 760))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings.png"))
    }

    /// The menu bar item in a few states, dark and light, at 4x.
    func testRenderMenuBar() throws {
        guard let dir = ProcessInfo.processInfo.environment["MACSTATS_RENDER_DIR"] else { throw XCTSkip("Set MACSTATS_RENDER_DIR to render") }
        typealias C = MacStatsMenuBarContent
        var quiet = C()
        quiet.temperature = .init(text: "106°", level: .normal)
        quiet.power = .init(text: "9 W", level: .normal)
        quiet.fan = .init(text: "Off", level: .normal, unit: "fans")
        quiet.bars = [.init(part: .efficiency, value: 0.47, level: .normal), .init(part: .performance, value: 0.06, level: .normal),
                      .init(part: .gpu, value: 0.28, level: .normal), .init(part: .memory, value: 0.59, level: .normal)]
        var busy = quiet
        busy.temperature = .init(text: "183°", level: .warning)
        busy.power = .init(text: "48 W", level: .normal)
        busy.fan = .init(text: "5.3k", level: .normal, unit: "rpm")
        busy.bars = [.init(part: .efficiency, value: 0.64, level: .normal), .init(part: .performance, value: 0.78, level: .warning),
                     .init(part: .gpu, value: 0.3, level: .normal), .init(part: .memory, value: 0.61, level: .normal)]
        var hot = busy
        hot.temperature = .init(text: "205°", level: .critical)
        hot.fan = .init(text: "7.8k", level: .normal, unit: "manual")
        hot.fansHeld = true
        hot.bars = [.init(part: .efficiency, value: 0.98, level: .critical), .init(part: .performance, value: 0.95, level: .critical),
                    .init(part: .gpu, value: 0.82, level: .warning), .init(part: .memory, value: 0.94, level: .critical)]
        var metersOnly = quiet
        metersOnly.temperature = nil
        metersOnly.power = nil
        metersOnly.fan = nil
        var noPerformance = quiet
        noPerformance.bars.remove(at: 1)
        let rows: [(C, Bool, Bool)] = [(quiet, true, true), (busy, true, true), (hot, true, true), (quiet, false, true), (hot, false, true),
                                       (metersOnly, true, true), (noPerformance, true, true), (quiet, true, false)]
        let scale: CGFloat = 4, rowH: CGFloat = 30, width: CGFloat = 140
        let sheet = NSImage(size: NSSize(width: width * scale, height: rowH * scale * CGFloat(rows.count)))
        sheet.lockFocus()
        for (i, row) in rows.enumerated() {
            let y = rowH * scale * CGFloat(rows.count - 1 - i)
            (row.1 ? NSColor(white: 0.06, alpha: 1) : NSColor(white: 0.9, alpha: 1)).setFill()
            NSRect(x: 0, y: y, width: width * scale, height: rowH * scale).fill()
            let image = MacStatsMenuBar.image(row.0, colourParts: row.2)
            NSAppearance(named: row.1 ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                image.draw(in: NSRect(x: 10 * scale, y: y + (rowH - image.size.height) / 2 * scale,
                                      width: image.size.width * scale, height: image.size.height * scale))
            }
        }
        sheet.unlockFocus()
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(sheet.tiffRepresentation)))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("menubar.png"))
    }
}
