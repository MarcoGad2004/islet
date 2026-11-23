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
        let size = NSSize(width: 27, height: 13)
        let image = NSImage(size: size, flipped: false) { _ in
            let ink = fillColor == nil ? NSColor.black : NSColor.labelColor
            let body = NSRect(x: 0.5, y: 0.75, width: 23, height: 11.5)
            let inner = body.insetBy(dx: 2, dy: 2)
            let share = CGFloat(min(max(percent, 0), 100)) / 100
            let fill = NSRect(x: inner.minX, y: inner.minY, width: max(1.5, inner.width * share), height: inner.height)
            (fillColor ?? ink).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1.8, yRadius: 1.8).fill()

            if let mark, let symbol = symbol(mark) {
                let s = symbol.size
                let at = NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height)
                // A gap around the mark so it reads over the fill.
                for dx in [-1.0, 0, 1.0] { for dy in [-1.0, 0, 1.0] where dx != 0 || dy != 0 {
                    symbol.draw(in: at.offsetBy(dx: dx, dy: dy), from: .zero, operation: .destinationOut, fraction: 1)
                } }
                tinted(symbol, ink).draw(in: at)
            }

            let outline = NSBezierPath(roundedRect: body, xRadius: 3.6, yRadius: 3.6)
            outline.lineWidth = 1
            ink.withAlphaComponent(0.4).setStroke()
            outline.stroke()
            let nub = NSBezierPath(roundedRect: NSRect(x: 24.4, y: 4.6, width: 1.8, height: 3.8), xRadius: 0.9, yRadius: 0.9)
            ink.withAlphaComponent(0.4).setFill()
            nub.fill()
            return true
        }
        image.isTemplate = fillColor == nil
        image.accessibilityDescription = "Battery \(percent)%" + (charging ? ", charging" : onAC ? ", plugged in" : "")
        return image
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: name.hasPrefix("bolt") ? 7.5 : 6.5, weight: .heavy))
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
