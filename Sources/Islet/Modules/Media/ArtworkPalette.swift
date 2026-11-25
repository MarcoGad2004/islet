import AppKit
import SwiftUI

/// Colours for the hidden-media peek (DESIGN.md "Media peek"): three taken across the artwork, left to right, each from
/// its band's most colourful pixels, then livened a touch so a dull cover still reads on black.
enum ArtworkPalette {
    /// No artwork: the glass look's own glow colours.
    static let fallback: [Color] = [.isletCyan, Color(hex: 0x5E5CE6), Color(hex: 0xFF5EA8)]

    /// Holds the image itself: an `ObjectIdentifier` alone is reused by the next image allocated at that address, which
    /// would hand a new cover the previous song's colours.
    @MainActor private static var cache: [ObjectIdentifier: (image: NSImage, colors: [Color])] = [:]

    @MainActor static func colors(_ image: NSImage?) -> [Color] {
        guard let image else { return fallback }
        let id = ObjectIdentifier(image)
        if let c = cache[id], c.image === image { return c.colors }
        let c = compute(image) ?? fallback
        if cache.count >= 4 { cache.removeAll() }
        cache[id] = (image, c)
        return c
    }

    private static func compute(_ image: NSImage) -> [Color]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let n = 12
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return nil }
        var out: [Color] = []
        for band in 0..<3 {
            var samples: [(r: Double, g: Double, b: Double, score: Double)] = []
            for y in 0..<n {
                for x in (band * n / 3)..<((band + 1) * n / 3) {
                    let i = (y * n + x) * 4
                    let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
                    let hi = max(r, g, b), lo = min(r, g, b)
                    let sat = hi > 0 ? (hi - lo) / hi : 0
                    samples.append((r, g, b, sat * hi))
                }
            }
            samples.sort { $0.score > $1.score }
            let top = samples.prefix(max(1, samples.count / 3))
            let k = Double(top.count)
            let avg = NSColor(srgbRed: top.map(\.r).reduce(0, +) / k, green: top.map(\.g).reduce(0, +) / k,
                              blue: top.map(\.b).reduce(0, +) / k, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            avg.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            out.append(Color(nsColor: NSColor(hue: h, saturation: min(1, s * 1.35 + 0.08),
                                              brightness: min(0.95, max(0.6, v * 1.15)), alpha: 1)))
        }
        return out
    }
}
