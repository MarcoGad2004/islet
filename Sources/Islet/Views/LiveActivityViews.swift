import SwiftUI

/// The activity's app: the Mac app's icon when there is one, else its first letter on a grey square.
struct ActivityIcon: View {
    let activity: LiveActivity
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = activity.icon {
                Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous).fill(Color(hex: 0x3A3A3C))
                    .overlay(Text(String(activity.app.prefix(1)).uppercased())
                        .font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(Color.isletText))
                    .padding(size * 0.04)
            }
        }
        .frame(width: size, height: size)
    }
}

/// One Live Activity in the panel (DESIGN.md "iPhone Live Activities", "In the panel"): built from its own text. The
/// app and a flag ("OVERDUE") on top; the title with the live value on the right; the other lines; its buttons.
struct LiveActivityCard: View {
    let store: IslandStore
    let activity: LiveActivity
    @Environment(\.isletGlass) private var glass

    static let width: CGFloat = 468
    static let top: CGFloat = 8
    static let gap: CGFloat = 8
    private static let padding: CGFloat = 12
    private static let header: CGFloat = 28
    private static let titleLine: CGFloat = 19
    private static let line: CGFloat = 15
    private static let buttons: CGFloat = 26

    /// The card's height for the shape: computed from its text, so the island can grow to it before it draws.
    static func height(_ a: LiveActivity) -> CGFloat {
        var h = padding + header + 6
        if let card = a.card {
            h += titleLines(card.title, value: a.value) * titleLine
            if !card.lines.isEmpty { h += 4 + CGFloat(card.lines.count) * line }
            if !card.buttons.isEmpty { h += 8 + buttons }
        } else {
            h += titleLine // the value alone
        }
        return h + padding
    }

    /// One or two lines of title, beside the value.
    private static func titleLines(_ title: String, value: String?) -> CGFloat {
        let valueWidth = value.map { ($0 as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)]).width + 12 } ?? 0
        let room = width - 2 * 14 - valueWidth
        let w = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold)]).width
        return w > room ? 2 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ActivityIcon(activity: activity, size: 28)
                Text(activity.app.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Color.isletTertiary).lineLimit(1)
                Spacer(minLength: 6)
                if let flag = activity.card?.flag {
                    Text(flag).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundStyle(Color(hex: 0xFF9F0A))
                }
            }
            .frame(height: Self.header)
            .padding(.bottom, 6)
            HStack(alignment: .top, spacing: 12) {
                if let card = activity.card {
                    Text(card.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.isletText)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Live Activity").font(.system(size: 13)).foregroundStyle(Color.isletSecondary)
                }
                Spacer(minLength: 0)
                if let v = activity.value {
                    Text(v).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText)
                        .lineLimit(1).fixedSize()
                        .contentTransition(.numericText()).animation(.easeOut(duration: 0.2), value: v)
                }
            }
            if let card = activity.card {
                if !card.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(card.lines.enumerated()), id: \.offset) { _, l in
                            Text(l).font(.system(size: 12)).foregroundStyle(Color.isletSecondary).lineLimit(1).frame(height: Self.line)
                        }
                    }
                    .padding(.top, 4)
                }
                if !card.buttons.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(card.buttons, id: \.self) { b in
                            Button { store.pressActivityButton(b, on: activity.id) } label: {
                                Text(b).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.isletText)
                                    .padding(.horizontal, 12).frame(height: Self.buttons)
                                    .background(IsletCard(shape: Capsule()))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, Self.padding)
        .frame(width: Self.width, height: Self.height(activity), alignment: .topLeading)
        .background(IsletCard(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }
}
