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
            HStack(spacing: 8) {
                budsColumn
                podColumn(level: reading.caseLevel, charging: reading.caseCharging)
            }
            .padding(.top, 6)
        }
        .frame(width: CGFloat(IslandLayout.earbudsCardWidth), height: CGFloat(IslandLayout.earbudsCardHeight), alignment: .top)
        .padding(.top, nh)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.name): earbuds \(reading.earbuds.map { "\($0) percent" } ?? "unknown"), case \(reading.caseLevel.map { "\($0) percent" } ?? "unknown")")
    }

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

    /// One earbud's picture: lit and seated while it is in the case, a little raised and fainter once it is out.
    private func budPicture(_ symbol: String, inCase: Bool) -> some View {
        Image(systemName: bud(symbol)).font(.system(size: 32)).foregroundStyle(Color.isletText)
            .opacity(split && !inCase ? 0.55 : 1)
            .offset(y: split && !inCase ? -5 : 0)
    }

    /// The earbuds' column. Together they sit side by side under one figure; with one out they part and each takes its
    /// own figure. It is one set of pieces moving on a spring, so taking them out one at a time glides both ways.
    private var budsColumn: some View {
        let apart: CGFloat = split ? 34 : 9
        return VStack(spacing: 2) {
            ZStack {
                budPicture(reading.budSymbols.left, inCase: reading.leftIn).offset(x: -apart)
                budPicture(reading.budSymbols.right, inCase: reading.rightIn).offset(x: apart)
            }
            .frame(height: 44)
            // The one figure fades out as the two part and each earbud's own fades in as it arrives under it, and back:
            // never the three at once.
            ZStack {
                level(reading.earbuds, charging: reading.earbudsCharging)
                    .opacity(split ? 0 : 1).animation(split ? .easeIn(duration: 0.1) : .easeOut(duration: 0.2).delay(0.14), value: split)
                level(reading.leftLevel, charging: reading.leftIn)
                    .opacity(split ? 1 : 0).animation(split ? .easeOut(duration: 0.2).delay(0.14) : .easeIn(duration: 0.1), value: split)
                    .offset(x: split ? -34 : -9)
                level(reading.rightLevel, charging: reading.rightIn)
                    .opacity(split ? 1 : 0).animation(split ? .easeOut(duration: 0.2).delay(0.14) : .easeIn(duration: 0.1), value: split)
                    .offset(x: split ? 34 : 9)
            }
            Text("Earbuds").font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
        }
        .frame(width: 132)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: split)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: reading.leftIn)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: reading.rightIn)
    }

    private func podColumn(level: Int?, charging: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: reading.symbols.pod).font(.system(size: 38)).foregroundStyle(Color.isletText).frame(height: 44)
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
            Text("Case").font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
        }
        .frame(width: 132)
    }
}
