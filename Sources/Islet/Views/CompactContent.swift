import SwiftUI

/// Content of the wings (60 pt either side of the notch) and the chin (300 x 36 body under the stem).
struct CompactContentView: View {
    let content: IslandContent
    let store: IslandStore
    let wings: Bool
    /// The lock-screen bar is a little taller than the notch.
    var lockBar = false
    /// Volume/brightness in the wide bar: the step bar sits in a short body under the wings.
    var levelBody = false
    /// Lock screen waiting for Command+Shift: the sentence sits in a short body under the wings.
    var hintBody = false
    /// Focus / Wi-Fi / Bluetooth events: wings wide enough for a name.
    var eventBar = false

    var body: some View {
        let nw = store.geometry?.width ?? 190, nh = store.geometry?.height ?? 34
        let barH = lockBar ? nh + IslandLayout.lockBarExtra : nh
        let activityWing: CGFloat? = if case .activity = content { CGFloat(store.activityWing) } else { nil }
        let wingW: CGFloat = activityWing ?? (eventBar ? CGFloat(IslandLayout.eventWing) : 60)
        Group {
            if wings {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // ZStack + clear keeps an empty wing at full width (an EmptyView would be dropped from the row).
                        ZStack { Color.clear; left }.frame(width: wingW, height: barH)
                        Spacer().frame(width: nw)
                        ZStack { Color.clear; right }.frame(width: wingW, height: barH)
                    }
                    .frame(width: nw + 2 * wingW, height: barH)
                    if levelBody, case .progress(let p) = content, let f = p.fraction {
                        // An update: the step and the bar for the whole job, under the wings.
                        HStack(spacing: 10) {
                            Text(p.state == .done && p.actionLabel != nil ? "\(p.text) · \(p.actionLabel!) ›" : p.text)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(progressTextColor(p))
                                .lineLimit(1).minimumScaleFactor(0.75)
                                .monospacedDigit().contentTransition(rolls(p) ? .numericText() : .opacity).animation(.easeInOut(duration: 0.2), value: p.text)
                            Spacer(minLength: 4)
                            UpdateBar(fraction: f, done: p.state == .done, failed: isFailed(p), width: 84)
                        }
                        .frame(width: nw + IslandLayout.wingsExtra - 2 * IslandLayout.levelSideInset,
                               height: IslandLayout.levelBodyHeight).offset(y: -1)
                    } else if levelBody, case .progress(let p) = content {
                        // The step, then the result, under the wings.
                        Text(p.state == .done && p.actionLabel != nil ? "\(p.text) · \(p.actionLabel!) ›" : p.text)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(progressTextColor(p))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .monospacedDigit().contentTransition(rolls(p) ? .numericText() : .opacity).animation(.easeInOut(duration: 0.2), value: p.text)
                            .frame(width: nw + IslandLayout.wingsExtra - 2 * IslandLayout.levelSideInset,
                                   height: IslandLayout.levelBodyHeight).offset(y: -1)
                    }
                    if levelBody, case .media = content {
                        // Hovered media: the song's name in the body; it rolls on a skip or previous swipe.
                        MediaTitleLane(store: store, fontSize: 12, spacing: 110)
                            .frame(width: nw + IslandLayout.wingsExtra - 2 * IslandLayout.levelSideInset,
                                   height: IslandLayout.levelBodyHeight).offset(y: -1)
                            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.1)),
                                                    removal: .opacity.animation(.easeOut(duration: 0.1))))
                    }
                    if levelBody, case .notification(let n) = content {
                        // A notification: "Title · message" under the wings; the newest fades across.
                        NotificationLine(item: n, size: 12)
                            .frame(width: nw + IslandLayout.wingsExtra - 2 * IslandLayout.levelSideInset,
                                   height: IslandLayout.levelBodyHeight, alignment: .leading).offset(y: -1)
                            .id(n.id).transition(.opacity.animation(.easeOut(duration: 0.2)))
                    }
                    if levelBody, case .activity(let a) = content {
                        // Hovering a Live Activity: what it is, under the wings.
                        Text(a.card.map { "\(a.app) · \($0.title)" } ?? a.app)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: nw + 2 * wingW - 2 * IslandLayout.levelSideInset,
                                   height: IslandLayout.levelBodyHeight).offset(y: -1)
                            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.1)),
                                                    removal: .opacity.animation(.easeOut(duration: 0.1))))
                    }
                    if levelBody, case .call(let c) = content {
                        // Hovering a call: who it is, under the wings.
                        Text("\(c.displayName) · \(c.muted ? "Muted" : c.kindLabel)")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: nw + IslandLayout.wingsExtra - 2 * IslandLayout.levelSideInset,
                                   height: IslandLayout.levelBodyHeight).offset(y: -1)
                            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.1)),
                                                    removal: .opacity.animation(.easeOut(duration: 0.1))))
                    }
                    if levelBody, case .event(let e) = content {
                        // Personal Hotspot: the phone's name under the wings.
                        Text(e.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: nw + IslandLayout.wingsExtra - 2 * IslandLayout.levelSideInset,
                                   height: IslandLayout.levelBodyHeight).offset(y: -1)
                    }
                    if levelBody, case .level(let l) = content {
                        // 16 steps spanning the bar with the same side inset as the icon and number above.
                        let inner = nw + IslandLayout.wingsExtra - 2 * IslandLayout.levelSideInset
                        StepBar(value: l.value, muted: l.muted, stepWidth: (inner - 15 * 3) / 16)
                            .animation(.levelGlide, value: l.value)
                            .frame(width: inner, height: IslandLayout.levelBodyHeight).offset(y: 1)
                    }
                    if hintBody {
                        Text("Press ⌘ + ⇧ to use Face Unlock")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: nw + IslandLayout.wingsExtra - 2 * 12, height: IslandLayout.lockHintBodyHeight)
                            .offset(y: -2)
                            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.2)),
                                                    removal: .opacity.animation(.easeOut(duration: 0.12))))
                    }
                }
                .frame(width: nw + 2 * wingW)
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
            if let m = store.media {
                MediaSlot(store: store, forward: false) {
                    ArtworkView(image: m.artwork, size: 22, radius: 6, playing: m.playing)
                        .opacity(store.morphFromPeek == nil ? 1 : 0)
                }
            }
        case .charge(let c): chargeIcon(c)
        case .unlock(let start): CheckPop(start: appears(start)).offset(x: -IslandLayout.checkInset)
        case .level(let l):
            Image(systemName: levelIcon(l)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText)
                .contentTransition(.symbolEffect(.replace)).animation(.levelGlide, value: levelIcon(l))
                .frame(width: 18).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, IslandLayout.levelSideInset - 2)
        case .locked:
            if store.lockHint && !hintBody {
                Text("⌘⇧").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletSecondary)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, IslandLayout.lockEdgeGap)
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
        case .event(let e):
            PopIcon(name: e.icon, color: eventTint(e))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, IslandLayout.levelSideInset)
        case .progress(let p):
            progressIcon(p).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, IslandLayout.levelSideInset)
        case .call(let c):
            if c.phase == .ringing { RingingPhone() } else { CallIcon(call: c) }
        case .notification(let n):
            NotificationIcon(item: n, size: 22).id(n.id).transition(.opacity.animation(.easeOut(duration: 0.2)))
        case .activity(let a):
            ActivityIcon(activity: a, size: 20)
        }
    }

    @ViewBuilder private var right: some View {
        switch content {
        case .media:
            if let m = store.media {
                MediaSlot(store: store, forward: true) { SourceIcon(bundleID: m.bundleID, size: 20, playing: m.playing) }
            }
        case .charge(let c):
            Text("\(c.percent)%").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(chargeColor(c, text: true))
        case .unlock(let start): PadlockView(start: appears(start)).offset(x: IslandLayout.lockInset)
        case .locked: PadlockView(start: nil).offset(x: IslandLayout.lockInset)
        case .level(let l):
            RollingNumber(value: l.value, off: l.muted).foregroundStyle(Color.isletText)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, IslandLayout.levelSideInset)
        case .progress(let p) where p.fraction != nil:
            // An update: the bar below turns into the check, so the wing only spins while it works.
            if case .working = p.state {
                ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 16, height: 16)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, IslandLayout.levelSideInset)
            }
        case .progress(let p):
            progressMark(p).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, IslandLayout.levelSideInset)
        case .event(let e) where levelBody:
            // The wing is too narrow for a word: the phone's cellular link, with the name in the body below.
            PopIcon(name: "cellularbars", color: eventTint(e))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, IslandLayout.levelSideInset)
        case .call(let c):
            if c.phase == .ringing { RingingPulse() } else { CallTimer(call: c) }
        case .notification:
            moreLabel
        case .activity(let a):
            // Its value (a timer, a score); the app's name when the value is a picture.
            if let v = a.value {
                Text(v).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText)
                    .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 12)
                    .contentTransition(.numericText()).animation(.easeOut(duration: 0.2), value: v)
            } else {
                Text(a.app).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 12)
            }
        case .event(let e):
            Text(e.kind == .focusOff ? "\(e.title) off" : e.title)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(e.kind == .focusOff ? Color.isletSecondary : Color.isletText)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, IslandLayout.levelSideInset)
        }
    }

    // MARK: Chin

    @ViewBuilder private var chin: some View {
        switch content {
        case .media:
            if let m = store.media {
                HStack(spacing: 10) {
                    MediaSlot(store: store, forward: false) {
                        ArtworkView(image: m.artwork, size: 22, radius: 6, playing: m.playing)
                            .opacity(store.morphFromPeek == nil ? 1 : 0)
                    }
                    MediaTitleLane(store: store, fontSize: 13, spacing: 100)
                    MediaSlot(store: store, forward: true) { SourceIcon(bundleID: m.bundleID, size: 20, playing: m.playing) }
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
                Image(systemName: levelIcon(l)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText)
                    .contentTransition(.symbolEffect(.replace)).animation(.levelGlide, value: levelIcon(l)).frame(width: 18)
                StepBar(value: l.value, muted: l.muted).animation(.levelGlide, value: l.value)
                Spacer(minLength: 2)
                RollingNumber(value: l.value, off: l.muted).foregroundStyle(Color.isletText)
                    .frame(width: 30, alignment: .trailing)
            }
        case .event(let e):
            HStack(spacing: 10) {
                PopIcon(name: e.icon, color: eventTint(e)).frame(width: 18)
                Text(e.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                Spacer(minLength: 4)
                Text(e.detail).font(.system(size: 13, weight: .semibold)).foregroundStyle(eventTint(e))
            }
        case .progress(let p):
            HStack(spacing: 10) {
                progressIcon(p).frame(width: 18)
                Text(p.text).font(.system(size: 13, weight: .semibold)).foregroundStyle(progressTextColor(p))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .monospacedDigit().contentTransition(rolls(p) ? .numericText() : .opacity).animation(.easeInOut(duration: 0.2), value: p.text)
                Spacer(minLength: 4)
                if let f = p.fraction {
                    if p.state == .done, let label = p.actionLabel { actionPill(label) }
                    UpdateBar(fraction: f, done: p.state == .done, failed: isFailed(p), width: 64)
                } else {
                    progressMark(p)
                }
            }
        case .call(let c):
            HStack(spacing: 10) {
                if c.phase == .ringing { RingingPhone().frame(width: 18) } else { CallIcon(call: c).frame(width: 18) }
                Text(c.phase == .ringing ? "Incoming call" : c.displayName)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                Spacer(minLength: 4)
                if c.phase == .active { CallTimer(call: c) }
            }
        case .activity(let a):
            HStack(spacing: 10) {
                ActivityIcon(activity: a, size: 20)
                Text(a.app).font(.system(size: 13)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                Spacer(minLength: 4)
                if let v = a.value {
                    Text(v).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText).lineLimit(1)
                        .contentTransition(.numericText()).animation(.easeOut(duration: 0.2), value: v)
                }
            }
        case .notification(let n):
            HStack(spacing: 10) {
                NotificationIcon(item: n, size: 20)
                NotificationLine(item: n, size: 13).frame(maxWidth: .infinity, alignment: .leading)
                moreLabel
            }
            .id(n.id).transition(.opacity.animation(.easeOut(duration: 0.2)))
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

    /// Three or more notifications: "N more" in the right wing or at the end of the chin.
    @ViewBuilder private var moreLabel: some View {
        if store.notificationCount >= 3 {
            Text("\(store.notificationCount - 1) more").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Color.isletSecondary).lineLimit(1).fixedSize()
                .contentTransition(.numericText()).animation(.easeOut(duration: 0.2), value: store.notificationCount)
                .transition(.opacity.combined(with: .offset(y: -4)).animation(.easeOut(duration: 0.25)))
        }
    }

    /// When this content has faded in: the animation's own clock starts then, so the closed lock is seen.
    /// Wings content fades in after 0.12 s, body shapes after 0.36 s (DESIGN.md "Motion").
    private func appears(_ start: Date) -> Date { start.addingTimeInterval(wings ? 0.12 : 0.36) }

    private func eventTint(_ e: IslandEvent) -> Color {
        if e.kind == .focusOn, let t = e.tint { return t }
        return switch e.kind {
        case .focusOn: Color(hex: 0xBF5AF2)
        case .focusOff: .isletSecondary
        case .wifi: .isletCyan
        case .hotspot: .isletGreen
        case .bluetooth: Color(hex: 0x0A84FF)
        }
    }

    // MARK: Connection progress

    private func progressTint(_ p: ConnectionProgress) -> Color {
        switch p.state {
        case .failed: .isletRed
        case .done, .working: p.tint ?? (p.hotspot ? .isletGreen : .isletCyan)
        }
    }

    /// Only a count (the download's percent) rolls its digits; a new step cross-fades.
    private func rolls(_ p: ConnectionProgress) -> Bool { p.text.hasSuffix("%") }

    private func isFailed(_ p: ConnectionProgress) -> Bool { if case .failed = p.state { true } else { false } }

    private func actionPill(_ label: String) -> some View {
        Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.isletText)
            .padding(.horizontal, 9).frame(height: 22).background(Capsule().fill(Color.white.opacity(0.16)))
            .fixedSize().transition(.opacity.animation(.easeOut(duration: 0.25)))
    }

    private func progressTextColor(_ p: ConnectionProgress) -> Color {
        if case .failed = p.state { return .isletRedText }
        return .isletText
    }

    /// The network's icon, breathing while it works.
    private func progressIcon(_ p: ConnectionProgress) -> some View {
        let working = if case .working = p.state { true } else { false }
        return Image(systemName: p.icon ?? (p.hotspot ? "personalhotspot" : "wifi"))
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(progressTint(p))
            .symbolEffect(.pulse, options: .repeating, isActive: working)
            .animation(.easeOut(duration: 0.25), value: p.state)
    }

    /// A spinner while it works, then a check or a cross that pops in. In the chin, a result that can be clicked shows
    /// its button instead of the check.
    @ViewBuilder private func progressMark(_ p: ConnectionProgress) -> some View {
        switch p.state {
        case .working: ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 16, height: 16)
        case .done where !wings && p.actionLabel != nil:
            actionPill(p.actionLabel!)
        case .done: PopIcon(name: "checkmark.circle.fill", color: .isletGreen, delay: 0)
        case .failed: PopIcon(name: "xmark.circle.fill", color: .isletRed, delay: 0)
        }
    }

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
        case .keyboard: l.value == 0 ? "light.min" : "light.max"
        case .volume: l.muted || l.value == 0 ? "speaker.slash.fill" : (l.value < 0.34 ? "speaker.wave.1.fill" : (l.value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
        }
    }
}

/// Icon that pops in from scale 0 with overshoot, 0.4 s.
struct PopIcon: View {
    var name: String
    var color: Color
    /// Waits for the shape to settle; 0 when the shape is already out (a result replacing a spinner).
    var delay: Double = 0.36
    @State private var on = false
    var body: some View {
        Image(systemName: name).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            .scaleEffect(on ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(delay)) { on = true } }
    }
}
