import SwiftUI

/// The AirPods case card (DESIGN.md "AirPods case"): the earbuds and the case as Apple's own symbols for that model,
/// each one's charge underneath and a bolt while it charges. (Models of each generation are for a later release.)
struct EarbudsView: View {
    let store: IslandStore
    let reading: EarbudsReading

    var body: some View {
        let nh = store.geometry?.height ?? 34
        VStack(spacing: 0) {
            Text(reading.name)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletSecondary)
                .padding(.top, 8)
            HStack(spacing: 56) {
                column(reading.symbols.earbuds, level: reading.earbuds, charging: reading.earbudsCharging, label: "Earbuds")
                column(reading.symbols.pod, level: reading.caseLevel, charging: reading.caseCharging, label: "Case")
            }
            .padding(.top, 6)
        }
        .frame(width: CGFloat(IslandLayout.earbudsCardWidth), height: CGFloat(IslandLayout.earbudsCardHeight), alignment: .top)
        .padding(.top, nh)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.name): earbuds \(reading.earbuds.map { "\($0) percent" } ?? "unknown"), case \(reading.caseLevel.map { "\($0) percent" } ?? "unknown")")
    }

    private func column(_ symbol: String, level: Int?, charging: Bool, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 38)).foregroundStyle(Color.isletText).frame(height: 44)
            HStack(spacing: 3) {
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.green)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(level.map { "\($0)%" } ?? "–")
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(!charging && (level ?? 100) <= 20 ? Color.isletRedText : Color.isletText)
            }
            .animation(.easeOut(duration: 0.2), value: charging)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
        }
    }
}
