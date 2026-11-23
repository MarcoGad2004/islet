#!/usr/bin/env swift
// Draws the Dynamic Peninsula app icon (a peninsula of black land joined to the top edge, in a turquoise sea) and writes Sources/Islet/Assets.xcassets/AppIcon.appiconset (run: swift scripts/make-icon.swift).
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)
    let rgb = CGColorSpaceCreateDeviceRGB()
    func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: rgb, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
    }

    // Tile: the standard macOS icon body (824 pt inside 1024) with a continuous-corner look.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: col(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(col(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()

    // The sea: shallow turquoise by the shore, deeper blue further out.
    let sea = CGGradient(colorsSpace: rgb, colors: [col(0x5EE6E0), col(0x1FA3C9), col(0x0B4F8A), col(0x072A55)] as CFArray,
                         locations: [0, 0.3, 0.72, 1])!
    ctx.drawLinearGradient(sea, start: CGPoint(x: 512, y: 900), end: CGPoint(x: 512, y: 100), options: [])
    // Sunlight on the water.
    let sun = CGGradient(colorsSpace: rgb, colors: [col(0xFFFFFF, 0.28), col(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sun, startCenter: CGPoint(x: 512, y: 600), startRadius: 0, endCenter: CGPoint(x: 512, y: 600),
                           endRadius: 420, options: [])

    // The land: the top edge (the mainland) and the peninsula joined to it, curving into it like the island's own
    // top corners do. A strip of sand runs round it, then the black land.
    let shoreY: CGFloat = 830          // the mainland's coastline
    let pw: CGFloat = 400, tip: CGFloat = 470, round: CGFloat = 120, fillet: CGFloat = 70
    func land(grow g: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let l = 512 - pw / 2 - g, r = 512 + pw / 2 + g, bottom = tip - g, shore = shoreY - g
        p.move(to: CGPoint(x: 0, y: 1024))
        p.addLine(to: CGPoint(x: 0, y: shore))
        p.addLine(to: CGPoint(x: l - fillet, y: shore))
        p.addQuadCurve(to: CGPoint(x: l, y: shore - fillet), control: CGPoint(x: l, y: shore))
        p.addLine(to: CGPoint(x: l, y: bottom + round))
        p.addQuadCurve(to: CGPoint(x: l + round, y: bottom), control: CGPoint(x: l, y: bottom))
        p.addLine(to: CGPoint(x: r - round, y: bottom))
        p.addQuadCurve(to: CGPoint(x: r, y: bottom + round), control: CGPoint(x: r, y: bottom))
        p.addLine(to: CGPoint(x: r, y: shore - fillet))
        p.addQuadCurve(to: CGPoint(x: r + fillet, y: shore), control: CGPoint(x: r, y: shore))
        p.addLine(to: CGPoint(x: 1024, y: shore))
        p.addLine(to: CGPoint(x: 1024, y: 1024))
        p.closeSubpath()
        return p
    }
    // Surf: two pale rings out in the water, following the coast.
    for (g, a) in [(CGFloat(78), CGFloat(0.22)), (CGFloat(128), CGFloat(0.12))] {
        ctx.addPath(land(grow: g)); ctx.setStrokeColor(col(0xFFFFFF, a)); ctx.setLineWidth(8); ctx.strokePath()
    }
    // Shallows, then the beach.
    ctx.addPath(land(grow: 44)); ctx.setFillColor(col(0x8FF2E6, 0.55)); ctx.fillPath()
    ctx.addPath(land(grow: 24)); ctx.setFillColor(col(0xF4D9A0)); ctx.fillPath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: col(0x6B4A1A, 0.45))
    ctx.addPath(land(grow: 0)); ctx.setFillColor(col(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    // The camera in the land, and a green status dot, as on the island.
    let lensY: CGFloat = 690
    ctx.setFillColor(col(0x15151C)); ctx.fillEllipse(in: CGRect(x: 512 - 34, y: lensY - 34, width: 68, height: 68))
    ctx.setFillColor(col(0x2A3A66)); ctx.fillEllipse(in: CGRect(x: 512 - 14, y: lensY - 14, width: 28, height: 28))
    ctx.setFillColor(col(0xFFFFFF, 0.35)); ctx.fillEllipse(in: CGRect(x: 512 - 4, y: lensY + 2, width: 8, height: 8))
    ctx.setFillColor(col(0x32D74B)); ctx.fillEllipse(in: CGRect(x: 512 + 70, y: lensY - 13, width: 26, height: 26))
    ctx.restoreGState()
    // Hairline highlight on the tile edge.
    ctx.addPath(tilePath); ctx.setStrokeColor(col(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sources/Islet/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try render(base * scale).write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let json: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]]).write(to: URL(fileURLWithPath: "Sources/Islet/Assets.xcassets/Contents.json"))
print("Wrote \(images.count) icons")
