import AppKit

/// The notch rectangle on the built-in display, measured from `NSScreen`.
/// All values are in points. `screenFrame` is in global (bottom-left origin) coordinates.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var width: CGFloat
    var height: CGFloat

    /// Size of the panel that hosts the island: big enough for the largest shape plus overshoot room.
    static let panelWidth: CGFloat = 560
    var panelHeight: CGFloat { height + IslandLayout.expandedBodyHeight + 24 }

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
}
