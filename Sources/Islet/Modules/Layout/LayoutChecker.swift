import AppKit
import ApplicationServices

/// Menu bar width check (DESIGN.md): wings only when 68 pt (60 + 8 margin) is free on both sides of the notch.
/// Left: the front app's menus, via Accessibility. Right: other apps' status item windows.
/// No Accessibility permission, or any failure: false, meaning the chin. Runs on events, never in a loop.
@MainActor
enum LayoutChecker {
    static let needed: CGFloat = 68

    /// The wide event bar (names) needs its 120 pt wings plus the same 8 pt margin on both sides.
    static let neededForEvents: CGFloat = CGFloat(IslandLayout.eventWing) + 8

    /// Free space left and right of the notch. Measured once per 0.25 s so asking for both layouts costs one pass.
    private static var cache: (time: CFTimeInterval, free: (CGFloat, CGFloat)?)?

    static func free(_ g: NotchGeometry) -> (left: CGFloat, right: CGFloat)? {
        let now = CACurrentMediaTime()
        if let c = cache, now - c.time < 0.25 { return c.free }
        var result: (CGFloat, CGFloat)?
        if AXIsProcessTrusted(), let l = freeLeft(g), let r = freeRight(g) { result = (l, r) }
        cache = (now, result)
        return result
    }

    static func wingsFit(_ g: NotchGeometry) -> Bool {
        guard let f = free(g) else { return false }
        return f.left >= needed && f.right >= needed
    }

    static func eventWingsFit(_ g: NotchGeometry) -> Bool {
        guard let f = free(g) else { return false }
        return f.left >= neededForEvents && f.right >= neededForEvents
    }

    private static func freeLeft(_ g: NotchGeometry) -> CGFloat? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.15)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement], !items.isEmpty else { return nil }

        var rightEdge: CGFloat = 0
        for item in items {
            var pos: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &pos) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success else { continue }
            var p = CGPoint.zero, s = CGSize.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &p)
            AXValueGetValue(size as! AXValue, .cgSize, &s)
            rightEdge = max(rightEdge, p.x + s.width)
        }
        guard rightEdge > 0 else { return nil }
        return (g.screenFrame.midX - g.width / 2) - rightEdge
    }

    private static func freeRight(_ g: NotchGeometry) -> CGFloat? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        // Window bounds are top-left based; the notch screen's top edge in that space:
        let primaryHeight = NSScreen.screens.first?.frame.height ?? g.screenFrame.height
        let topY = primaryHeight - g.screenFrame.maxY
        let notchRight = g.screenFrame.midX + g.width / 2
        let me = ProcessInfo.processInfo.processIdentifier
        var nearest = g.screenFrame.maxX
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 25, (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], width > 0,
                  y >= topY - 1, y <= topY + g.height, x >= notchRight - 1 else { continue }
            nearest = min(nearest, x)
        }
        return nearest - notchRight
    }
}
