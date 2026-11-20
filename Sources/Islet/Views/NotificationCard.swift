import SwiftUI

/// A notification under the notch (DESIGN.md "Notifications"): the 360 x 72 card, or the 380 x 132 one a swipe down
/// opens with the whole message and the banner's Close and Show.
struct NotificationCard: View {
    let store: IslandStore
    let item: NotificationItem
    let tall: Bool
    @AppStorage(NotificationWatcher.hideTextKey) private var hideText = false

    var body: some View {
        let nh = store.geometry?.height ?? 34
        Group {
            if tall { tallCard } else { card }
        }
        .padding(.top, nh)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var line: String { hideText ? "" : item.line }

    private var card: some View {
        HStack(spacing: 12) {
            NotificationIcon(item: item, count: store.notificationCount)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("now").font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
                }
                if !line.isEmpty {
                    Text(line).font(.system(size: 12)).foregroundStyle(Color.isletSecondary).lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(width: CGFloat(IslandLayout.notificationWidth), height: CGFloat(IslandLayout.notificationHeight))
        // Another one arriving fades across in place.
        .id(item.id)
        .transition(.opacity.animation(.easeOut(duration: 0.2)))
        .animation(.easeOut(duration: 0.2), value: item.id)
    }

    private var tallCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                NotificationIcon(item: item, count: store.notificationCount)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(item.app) · now").font(.system(size: 11)).foregroundStyle(Color.isletTertiary).lineLimit(1)
                    }
                    if !line.isEmpty {
                        Text(line).font(.system(size: 12)).lineSpacing(2).foregroundStyle(Color(hex: 0xC7C7CC))
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Spacer()
                pill("Close", primary: false) { store.endNotification(.closed) }
                pill("Show", primary: true) { store.endNotification(.shown) }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18))
        .frame(width: CGFloat(IslandLayout.notificationTallWidth), height: CGFloat(IslandLayout.notificationTallHeight))
    }

    private func pill(_ label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(primary ? Color.black : Color.isletText)
                .padding(.horizontal, 14).frame(height: 28)
                .background(Capsule().fill(primary ? Color.isletText : Color.isletRing))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The app's icon (34 pt), with a count from the second notification on.
struct NotificationIcon: View {
    let item: NotificationItem
    let count: Int

    var body: some View {
        Group {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x3A3A3C))
                    .overlay(Image(systemName: "bell.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.isletText))
                    .padding(1)
            }
        }
        .frame(width: 34, height: 34)
        .overlay(alignment: .bottomTrailing) {
            if count > 1 {
                Text("\(count)").font(.system(size: 10, weight: .bold)).monospacedDigit().foregroundStyle(Color.isletText)
                    .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Color(hex: 0x3A3A3C)))
                    .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                    .offset(x: 6, y: 5)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: count)
            }
        }
    }
}
