import AppKit

/// What Islet's menu bar icon looks like: the pill, or a battery that can stand in for macOS's own (DESIGN.md
/// "Menu bar battery").
enum MenuBarIconStyle: String, CaseIterable {
    case pill, battery
    static let key = "menuBarIconStyle"
    static var current: MenuBarIconStyle {
        UserDefaults.standard.string(forKey: key).flatMap(MenuBarIconStyle.init) ?? .pill
    }
}

/// What a click on the battery icon opens: its stats, or the island's control center.
enum BatteryIconClick: String, CaseIterable {
    case stats, controls
    static let key = "batteryIconClick"
    static var current: BatteryIconClick {
        UserDefaults.standard.string(forKey: key).flatMap(BatteryIconClick.init) ?? .stats
    }
}

enum MenuBarBattery {
    /// Show the percentage beside the battery icon (on unless turned off).
    static let percentKey = "batteryIconPercent"
    static var showsPercent: Bool { UserDefaults.standard.object(forKey: percentKey) as? Bool ?? true }

    /// macOS colours its battery icon red at this charge and below while on battery.
    static let lowPercent = 10

    /// The icon after macOS's own: a pale outline with the charge as a solid fill, a bolt while charging, a plug when
    /// plugged in and not charging. Red when low, yellow in Low Power Mode; otherwise a template image, so it follows
    /// the menu bar's colours.
    static func image(percent: Int, charging: Bool, onAC: Bool, lowPower: Bool) -> NSImage {
        let low = !onAC && percent <= lowPercent
        let fillColor: NSColor? = low ? .systemRed : lowPower ? .systemYellow : nil
        let mark: String? = charging ? "bolt.fill" : onAC ? "powerplug.portrait.fill" : nil
        // The shared shape (`BatteryMetrics`), 13.5 pt tall.
        let h: CGFloat = 13.5
        let size = NSSize(width: ceil(BatteryMetrics.width(height: h)) + 1, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            let ink = fillColor == nil ? NSColor.black : NSColor.labelColor
            let line = BatteryMetrics.lineWidth(height: h)
            let body = NSRect(x: line / 2, y: (15 - h) / 2 + line / 2, width: h * BatteryMetrics.bodyLength - line, height: h - line)
            let inner = body.insetBy(dx: h * BatteryMetrics.inset - line / 2, dy: h * BatteryMetrics.inset - line / 2)
            let share = CGFloat(min(max(percent, 0), 100)) / 100
            let fill = NSRect(x: inner.minX, y: inner.minY, width: max(1.5, inner.width * share), height: inner.height)
            (fillColor ?? ink).setFill()
            let fillCorner = max(1, h * (BatteryMetrics.corner - BatteryMetrics.inset))
            NSBezierPath(roundedRect: fill, xRadius: fillCorner, yRadius: fillCorner).fill()

            if let mark, let symbol = symbol(mark) {
                let s = symbol.size
                let at = NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height)
                // A gap around the mark so it reads over the fill.
                for i in 0..<16 {
                    let angle = Double(i) / 16 * 2 * .pi
                    symbol.draw(in: at.offsetBy(dx: 1.1 * cos(angle), dy: 1.1 * sin(angle)), from: .zero,
                                operation: .destinationOut, fraction: 1)
                }
                tinted(symbol, ink).draw(in: at)
            }

            let corner = h * BatteryMetrics.corner - line / 2
            let outline = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)
            outline.lineWidth = line
            ink.withAlphaComponent(BatteryMetrics.outlineOpacity).setStroke()
            outline.stroke()
            let nubW = h * BatteryMetrics.nubWidth, nubH = h * BatteryMetrics.nubHeight
            let nubRect = NSRect(x: h * (BatteryMetrics.bodyLength + BatteryMetrics.gap), y: 7.5 - nubH / 2, width: nubW, height: nubH)
            let nub = NSBezierPath(roundedRect: nubRect, xRadius: nubW / 2, yRadius: nubW / 2)
            ink.withAlphaComponent(BatteryMetrics.outlineOpacity).setFill()
            nub.fill()
            return true
        }
        image.isTemplate = fillColor == nil
        image.accessibilityDescription = "Battery \(percent)%" + (charging ? ", charging" : onAC ? ", plugged in" : "")
        return image
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: name.hasPrefix("bolt") ? 8.5 : 7.5, weight: .heavy))
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
