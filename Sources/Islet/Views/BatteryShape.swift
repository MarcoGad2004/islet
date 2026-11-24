import SwiftUI

/// One battery shape everywhere, after Apple's 2027 battery (DESIGN.md "Menu bar battery"): the menu bar icon, the
/// battery page, quick info and the charging animation all draw from these proportions, given as shares of the body's
/// height, so only the height changes between them. There is no outline: the body is a solid pale track and the charge
/// fills it from the left, edge to edge, its right end cut straight.
enum BatteryMetrics {
    /// The body is twice as long as it is tall.
    static let bodyLength: CGFloat = 2
    /// The gap before the nub, and the nub's width and height.
    static let gap: CGFloat = 0.067
    static let nubWidth: CGFloat = 0.148
    static let nubHeight: CGFloat = 0.37
    static let corner: CGFloat = 0.33
    /// The empty part of the body and the nub.
    static let trackOpacity = 0.4
    /// The least fill shown above 0%, so a nearly empty battery still shows a sliver.
    static let minFill: CGFloat = 0.12

    /// The whole battery's width, nub included, for a body this tall.
    static func width(height h: CGFloat) -> CGFloat { h * (bodyLength + gap + nubWidth) }
    /// How far the fill reaches across a body this tall, for a 0...1 level.
    static func fillWidth(level: Double, height h: CGFloat) -> CGFloat {
        let l = CGFloat(min(max(level, 0), 1))
        return l == 0 ? 0 : max(h * minFill, h * bodyLength * l)
    }
}

/// The battery's track, nub and charge fill, with an optional mark (a bolt) centred on the body. Give it a frame of
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
            let shape = RoundedRectangle(cornerRadius: h * BatteryMetrics.corner, style: .continuous)
            HStack(spacing: h * BatteryMetrics.gap) {
                ZStack(alignment: .leading) {
                    shape.fill(outline.opacity(BatteryMetrics.trackOpacity))
                    Rectangle().fill(tint)
                        .frame(width: BatteryMetrics.fillWidth(level: level, height: h))
                }
                .frame(width: w, height: h)
                .clipShape(shape)
                .overlay { mark() }
                UnevenRoundedRectangle(bottomTrailingRadius: h * BatteryMetrics.nubWidth,
                                       topTrailingRadius: h * BatteryMetrics.nubWidth, style: .continuous)
                    .fill(outline.opacity(BatteryMetrics.trackOpacity))
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
