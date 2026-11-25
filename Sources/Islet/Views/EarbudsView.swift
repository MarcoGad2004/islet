import AppKit
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
            HStack(spacing: 44) {
                budsColumn
                column(.pod, level: reading.caseLevel, charging: reading.caseCharging, label: "Case")
            }
            .padding(.top, 6)
        }
        .frame(width: CGFloat(IslandLayout.earbudsCardWidth), height: CGFloat(IslandLayout.earbudsCardHeight), alignment: .top)
        .padding(.top, nh)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.name): earbuds \(reading.earbuds.map { "\($0) percent" } ?? "unknown"), case \(reading.caseLevel.map { "\($0) percent" } ?? "unknown")")
    }

    private enum Part { case buds, pod }

    /// An earbud's symbol, or the model's own earbuds if this macOS lacks the single one.
    private func bud(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : reading.symbols.earbuds
    }

    /// One or both earbuds out of the case: each shows its own charge, with a bolt only on one still charging in it.
    private var split: Bool { !(reading.leftIn && reading.rightIn) }

    private func level(_ n: Int?, charging: Bool) -> some View {
        HStack(spacing: 3) {
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.green)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(n.map { "\($0)%" } ?? "–").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(!charging && (n ?? 100) <= 20 ? Color.isletRedText : Color.isletText)
        }
        .animation(.easeOut(duration: 0.2), value: charging)
    }

    private func oneBud(_ symbol: String, level n: Int?, inCase: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: bud(symbol)).font(.system(size: 30)).foregroundStyle(Color.isletText).opacity(inCase ? 1 : 0.6).frame(height: 44)
            level(n, charging: inCase)
        }
    }

    @ViewBuilder private var budsColumn: some View {
        if split {
            VStack(spacing: 2) {
                HStack(spacing: 14) {
                    oneBud(reading.budSymbols.left, level: reading.leftLevel, inCase: reading.leftIn)
                    oneBud(reading.budSymbols.right, level: reading.rightLevel, inCase: reading.rightIn)
                }
                Text("Earbuds").font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
            }
        } else {
            column(.buds, level: reading.earbuds, charging: reading.earbudsCharging, label: "Earbuds")
        }
    }

    @ViewBuilder private func picture(_ part: Part) -> some View {
        switch part {
        case .pod:
            Image(systemName: reading.symbols.pod).font(.system(size: 38)).foregroundStyle(Color.isletText)
        case .buds:
            // Each earbud in its own place: lit while it sits in the case, faint once it is out.
            HStack(spacing: 2) {
                Image(systemName: bud(reading.budSymbols.left)).opacity(reading.leftIn ? 1 : 0.2)
                Image(systemName: bud(reading.budSymbols.right)).opacity(reading.rightIn ? 1 : 0.2)
            }
            .font(.system(size: 34)).foregroundStyle(Color.isletText)
            .animation(.easeOut(duration: 0.25), value: reading.leftIn)
            .animation(.easeOut(duration: 0.25), value: reading.rightIn)
        }
    }

    private func column(_ part: Part, level: Int?, charging: Bool, label: String) -> some View {
        VStack(spacing: 2) {
            picture(part).frame(height: 44)
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
