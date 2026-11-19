#!/usr/bin/env swift
// Draws the Islet app icon and writes Sources/Islet/Assets.xcassets/AppIcon.appiconset (run: swift scripts/make-icon.swift).
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
    let bg = CGGradient(colorsSpace: rgb, colors: [col(0x3B4A7A), col(0x1B2038), col(0x0C0E1A)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft cyan glow behind the face grid.
    let glow = CGGradient(colorsSpace: rgb, colors: [col(0x64D2FF, 0.35), col(0x64D2FF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 430), startRadius: 0, endCenter: CGPoint(x: 512, y: 430), endRadius: 330, options: [])

    // The island: a black capsule hanging from the top edge, like the notch.
    let w: CGFloat = 520, h: CGFloat = 150, top: CGFloat = 924
    let island = CGPath(roundedRect: CGRect(x: 512 - w / 2, y: top - h, width: w, height: h + 60), cornerWidth: 75, cornerHeight: 75, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: col(0x000000, 0.5))
    ctx.addPath(island); ctx.setFillColor(col(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    // Camera lens and a green status dot inside the island.
    ctx.setFillColor(col(0x15151C)); ctx.fillEllipse(in: CGRect(x: 512 - 26, y: top - h / 2 - 26 + 18, width: 52, height: 52))
    ctx.setFillColor(col(0x2A3A66)); ctx.fillEllipse(in: CGRect(x: 512 - 11, y: top - h / 2 - 11 + 18, width: 22, height: 22))
    ctx.setFillColor(col(0x32D74B)); ctx.fillEllipse(in: CGRect(x: 512 + 150, y: top - h / 2 - 14 + 18, width: 28, height: 28))

    // Face-scan dot grid inside a ring, below the island.
    let cx: CGFloat = 512, cy: CGFloat = 430, ring: CGFloat = 215
    ctx.setStrokeColor(col(0x64D2FF, 0.9)); ctx.setLineWidth(14)
    ctx.strokeEllipse(in: CGRect(x: cx - ring, y: cy - ring, width: ring * 2, height: ring * 2))
    let step: CGFloat = 52
    for i in -3...3 { for j in -3...3 {
        let x = cx + CGFloat(i) * step, y = cy + CGFloat(j) * step
        if hypot(x - cx, y - cy) > ring - 62 { continue }
        let r: CGFloat = 11
        ctx.setFillColor(col(0xE8F6FF, 0.92)); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    } }
    ctx.restoreGState()
    // Hairline highlight on the tile edge.
    ctx.addPath(tilePath); ctx.setStrokeColor(col(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = "Sources/Islet/Assets.xcassets/AppIcon.appiconset"
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
