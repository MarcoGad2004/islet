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

    /// The icon after macOS's own (the 2027 design): a pale solid body with the charge filling it from the left, a bolt
    /// while charging, a plug when plugged in and not charging. The fill is green while the battery is actually charging
    /// (not merely plugged in), red when low, yellow in Low Power Mode; otherwise a template image, so it follows the menu
    /// bar's colours. The empty part, the nub and the bolt keep the menu bar's colour.
    static func image(percent: Int, charging: Bool, onAC: Bool, lowPower: Bool) -> NSImage {
        let low = !onAC && percent <= lowPercent
        let fillColor: NSColor? = charging ? .systemGreen : low ? .systemRed : lowPower ? .systemYellow : nil
        let mark: String? = charging ? "bolt.fill" : onAC ? "powerplug.portrait.fill" : nil
        // The shared shape (`BatteryMetrics`), 13.5 pt tall.
        let h: CGFloat = 13.5
        // Clear space either side so it doesn't crowd the menu bar icons next to it.
        let pad: CGFloat = 3
        let size = NSSize(width: ceil(BatteryMetrics.width(height: h)) + 1 + 2 * pad, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            let ink = fillColor == nil ? NSColor.black : NSColor.labelColor
            let body = NSRect(x: pad, y: (15 - h) / 2, width: h * BatteryMetrics.bodyLength, height: h)
            let corner = h * BatteryMetrics.corner
            let shape = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)
            ink.withAlphaComponent(BatteryMetrics.trackOpacity).setFill()
            shape.fill()
            let fillWidth = BatteryMetrics.fillWidth(level: Double(percent) / 100, height: h)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            (fillColor ?? ink).setFill()
            NSRect(x: body.minX, y: body.minY, width: fillWidth, height: h).fill()
            NSGraphicsContext.restoreGraphicsState()

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

            let nubW = h * BatteryMetrics.nubWidth, nubH = h * BatteryMetrics.nubHeight
            let nubRect = NSRect(x: pad + h * (BatteryMetrics.bodyLength + BatteryMetrics.gap), y: 7.5 - nubH / 2, width: nubW, height: nubH)
            // Flat against the body, round on the outside.
            let nub = NSBezierPath()
            nub.move(to: NSPoint(x: nubRect.minX, y: nubRect.minY))
            nub.appendArc(from: NSPoint(x: nubRect.maxX, y: nubRect.minY), to: NSPoint(x: nubRect.maxX, y: nubRect.maxY), radius: nubW)
            nub.appendArc(from: NSPoint(x: nubRect.maxX, y: nubRect.maxY), to: NSPoint(x: nubRect.minX, y: nubRect.maxY), radius: nubW)
            nub.line(to: NSPoint(x: nubRect.minX, y: nubRect.maxY))
            nub.close()
            ink.withAlphaComponent(BatteryMetrics.trackOpacity).setFill()
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
