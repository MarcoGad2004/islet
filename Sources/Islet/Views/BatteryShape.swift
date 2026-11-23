import SwiftUI

/// One battery shape everywhere, after the menu bar battery (DESIGN.md "Menu bar battery"): the menu bar icon, the
/// battery page, quick info and the charging animation all draw from these proportions, given as shares of the body's
/// height, so only the height changes between them.
enum BatteryMetrics {
    /// The body is twice as long as it is tall.
    static let bodyLength: CGFloat = 2
    /// The gap before the nub, and the nub's width and height.
    static let gap: CGFloat = 0.067
    static let nubWidth: CGFloat = 0.148
    static let nubHeight: CGFloat = 0.311
    static let corner: CGFloat = 0.296
    /// Between the outline and the fill.
    static let inset: CGFloat = 0.148
    static let line: CGFloat = 0.074
    static let outlineOpacity = 0.4

    /// The whole battery's width, nub included, for a body this tall.
    static func width(height h: CGFloat) -> CGFloat { h * (bodyLength + gap + nubWidth) }
    static func lineWidth(height h: CGFloat) -> CGFloat { max(1, h * line) }
}

/// The battery's outline, nub and charge fill, with an optional mark (a bolt) centred on the body. Give it a frame of
/// `BatteryMetrics.width(height:)` by the height.
struct BatteryBody<Mark: View>: View {
    /// 0...1.
    var level: Double
    var tint: Color
    var outline: Color = .isletText
    @ViewBuilder var mark: () -> Mark

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = h * BatteryMetrics.bodyLength
            let inset = h * BatteryMetrics.inset
            let corner = h * BatteryMetrics.corner
            HStack(spacing: h * BatteryMetrics.gap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(outline.opacity(BatteryMetrics.outlineOpacity), lineWidth: BatteryMetrics.lineWidth(height: h))
                    RoundedRectangle(cornerRadius: max(1, corner - inset), style: .continuous)
                        .fill(tint)
                        .frame(width: max(1.5, (w - 2 * inset) * CGFloat(min(max(level, 0), 1))), height: h - 2 * inset)
                        .padding(.leading, inset)
                }
                .frame(width: w, height: h)
                .overlay { mark() }
                RoundedRectangle(cornerRadius: h * BatteryMetrics.nubWidth / 2, style: .continuous)
                    .fill(outline.opacity(BatteryMetrics.outlineOpacity))
                    .frame(width: h * BatteryMetrics.nubWidth, height: h * BatteryMetrics.nubHeight)
            }
        }
    }
}

extension BatteryBody where Mark == EmptyView {
    init(level: Double, tint: Color, outline: Color = .isletText) {
        self.init(level: level, tint: tint, outline: outline) { EmptyView() }
    }
}
