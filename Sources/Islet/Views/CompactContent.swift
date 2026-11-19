import SwiftUI

/// Content of the wings (60 pt either side of the notch) and the chin (300 x 36 body under the stem).
struct CompactContentView: View {
    let content: IslandContent
    let store: IslandStore
    let wings: Bool

    var body: some View {
        let nw = store.geometry?.width ?? 190, nh = store.geometry?.height ?? 34
        Group {
            if wings {
                HStack(spacing: 0) {
                    left.frame(width: 60)
                    Spacer().frame(width: nw)
                    right.frame(width: 60)
                }
                .frame(width: nw + IslandLayout.wingsExtra, height: nh)
            } else {
                chin
                    .padding(.horizontal, 16)
                    .frame(width: IslandLayout.chinWidth, height: IslandLayout.chinHeight)
                    .padding(.top, nh)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Wings

    @ViewBuilder private var left: some View {
        switch content {
        case .media:
            if let m = store.media { ArtworkView(image: m.artwork, size: 22, radius: 6, playing: m.playing) }
        case .charge(let c): chargeIcon(c)
        case .unlock(let start): CheckPop(start: appears(start)).offset(x: -IslandLayout.wingInset)
        case .locked, .level: EmptyView()
        }
    }

    @ViewBuilder private var right: some View {
        switch content {
        case .media: LevelBars(playing: store.media?.playing ?? false)
        case .charge(let c):
            Text("\(c.percent)%").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(chargeColor(c, text: true))
        case .unlock(let start): PadlockView(start: appears(start)).offset(x: IslandLayout.wingInset)
        case .locked: PadlockView(start: nil).offset(x: IslandLayout.wingInset)
        case .level: EmptyView()
        }
    }

    // MARK: Chin

    @ViewBuilder private var chin: some View {
        switch content {
        case .media:
            if let m = store.media {
                HStack(spacing: 10) {
                    ArtworkView(image: m.artwork, size: 22, radius: 6, playing: m.playing)
                    MarqueeText(text: m.artist.isEmpty ? m.title : "\(m.title) · \(m.artist)")
                    LevelBars(playing: m.playing)
                }
            }
        case .charge(let c):
            HStack(spacing: 10) {
                chargeIcon(c)
                Text(chargeLabel(c)).font(.system(size: 13, weight: .semibold)).foregroundStyle(c.kind == .low ? Color.isletRedText : Color.isletText)
                Spacer(minLength: 4)
                Text("\(c.percent)%").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(chargeColor(c, text: true))
            }
        case .level(let l):
            HStack(spacing: 10) {
                Image(systemName: levelIcon(l)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).frame(width: 18)
                StepBar(steps: l.steps, muted: l.muted)
                Spacer(minLength: 2)
                Text(l.muted ? "Off" : "\(Int((l.value * 100).rounded()))")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText)
                    .frame(width: 30, alignment: .trailing)
            }
        case .locked:
            PadlockView(start: nil)
        case .unlock(let start):
            HStack(spacing: 10) {
                PadlockView(start: appears(start))
                TimelineView(.animation) { ctx in
                    let a = min(max((ctx.date.timeIntervalSince(appears(start)) - 0.8) / 0.3, 0), 1)
                    Text("Unlocked").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletGreen).opacity(a)
                }
            }
        }
    }

    // MARK: Helpers

    /// When this content has faded in: the animation's own clock starts then, so the closed lock is seen.
    /// Wings content fades in after 0.12 s, body shapes after 0.36 s (DESIGN.md "Motion").
    private func appears(_ start: Date) -> Date { start.addingTimeInterval(wings ? 0.12 : 0.36) }

    private func chargeColor(_ c: ChargeEvent, text: Bool) -> Color { c.kind == .low ? (text ? .isletRedText : .isletRed) : .isletGreen }

    @ViewBuilder private func chargeIcon(_ c: ChargeEvent) -> some View {
        let name = c.kind == .connected ? "bolt.fill" : c.kind == .full ? "battery.100" : (c.percent <= 10 ? "battery.0" : "battery.25")
        PopIcon(name: name, color: chargeColor(c, text: false))
    }

    private func chargeLabel(_ c: ChargeEvent) -> String {
        switch c.kind {
        case .full: return "Fully charged"
        case .low: return "Low battery"
        case .connected:
            guard let m = c.minutesToFull else { return "Charging" }
            return "Charging · \(m / 60):\(String(format: "%02d", m % 60)) to full"
        }
    }

    private func levelIcon(_ l: LevelState) -> String {
        switch l.kind {
        case .brightness: "sun.max.fill"
        case .volume: l.muted || l.value == 0 ? "speaker.slash.fill" : (l.value < 0.34 ? "speaker.wave.1.fill" : (l.value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
        }
    }
}

/// Icon that pops in from scale 0 with overshoot, 0.4 s.
struct PopIcon: View {
    var name: String
    var color: Color
    @State private var on = false
    var body: some View {
        Image(systemName: name).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            .scaleEffect(on ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.36)) { on = true } }
    }
}
