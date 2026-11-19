import AppKit

/// The notch rectangle on the built-in display, measured from `NSScreen`.
/// All values are in points. `screenFrame` is in global (bottom-left origin) coordinates.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var width: CGFloat
    var height: CGFloat
    /// No notch: the island hangs from the bottom of the menu bar under Islet's menu bar icon instead. It is
    /// invisible when idle and draws as a flat-topped card (see `IslandStore.targetMetrics`).
    var virtual = false

    /// The stand-in notch for `virtual`: narrower than a real one (the volume bar and the lock hint still fit), and as tall as a real one so the wing layouts fit unchanged.
    static let virtualWidth: CGFloat = 100
    static let virtualHeight: CGFloat = 32

    /// Size of the panel that hosts the island: big enough for the largest shape plus overshoot room.
    static let panelWidth: CGFloat = 560
    var panelHeight: CGFloat { height + IslandLayout.expandedListBodyHeight + 24 }

    /// Panel frame in global coordinates, centred at the top of the screen.
    var panelFrame: CGRect {
        CGRect(x: screenFrame.midX - Self.panelWidth / 2,
               y: screenFrame.maxY - panelHeight,
               width: Self.panelWidth, height: panelHeight)
    }

    /// Converts a global (bottom-left origin) point to panel coordinates (top-left origin).
    func panelPoint(fromGlobal p: CGPoint) -> CGPoint {
        let f = panelFrame
        return CGPoint(x: p.x - f.minX, y: f.maxY - p.y)
    }

    /// The built-in notched display, or nil when there is none (lid closed, no notch).
    @MainActor static func current() -> NotchGeometry? {
        #if DEBUG
        // `Islet -IsletNoNotch YES` behaves like a Mac without a notch, to try the menu bar mode on a notched one.
        if UserDefaults.standard.bool(forKey: "IsletNoNotch") { return nil }
        #endif
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { return nil }
        let height = screen.safeAreaInsets.top
        let width: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = right.minX - left.maxX
        } else {
            width = 190 // fallback to the 14" size from DESIGN.md
        }
        return NotchGeometry(screenFrame: screen.frame, width: width, height: height)
    }

    /// The menu bar stand-in: centred under `anchorX` (the menu bar icon) with its top at `menuBarBottom`, kept far
    /// enough from the screen's edges that the 500 pt panel stays on screen.
    static func underMenuBar(anchorX: CGFloat, menuBarBottom: CGFloat, screen: CGRect) -> NotchGeometry {
        let half = CGFloat(IslandLayout.expandedWidth) / 2 + 8
        let x = min(max(anchorX, screen.minX + half), screen.maxX - half)
        return NotchGeometry(screenFrame: CGRect(x: x - 1, y: screen.minY, width: 2, height: menuBarBottom - screen.minY),
                             width: virtualWidth, height: virtualHeight, virtual: true)
    }
}

/// What Islet does on a Mac (or display setup) without a notch.
enum NotchlessStyle: String, CaseIterable {
    /// The island drops down from Islet's menu bar icon.
    case menuBar
    /// No island at all; face unlock and the rest keep working without it.
    case off

    static let key = "notchlessStyle"
    static var current: NotchlessStyle {
        UserDefaults.standard.string(forKey: key).flatMap(NotchlessStyle.init) ?? .menuBar
    }
}
