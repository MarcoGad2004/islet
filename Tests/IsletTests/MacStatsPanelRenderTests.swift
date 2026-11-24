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
}
