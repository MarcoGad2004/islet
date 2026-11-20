import SwiftUI

/// Ringing, left wing: a green phone that wiggles on a 1.3 s loop (DESIGN.md "Calls").
struct RingingPhone: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 1.3) / 1.3
            let k = t / 0.45
            let angle = k < 1 ? sin(k * 4 * .pi) * 16 * (1 - k) : 0
            Image(systemName: "phone.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.isletGreen)
                .rotationEffect(.degrees(angle))
        }
    }
}

/// Ringing, right wing: two green rings pulsing out, 1.5 s each, half a loop apart.
struct RingingPulse: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { ctx in
            let e = ctx.date.timeIntervalSince(start)
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let p = (e + Double(i) * 0.75).truncatingRemainder(dividingBy: 1.5) / 1.5
                    Circle().stroke(Color.isletGreen, lineWidth: 2).frame(width: 18, height: 18)
                        .scaleEffect(0.35 + 0.9 * p).opacity(0.95 * (1 - p))
                }
            }
            .frame(width: 22, height: 22)
        }
    }
}

/// In a call: a green camera (or phone), or a red crossed-out mic while muted.
struct CallIcon: View {
    let call: CallState
    var body: some View {
        Image(systemName: call.muted ? "mic.slash.fill" : (call.video ? "video.fill" : "phone.fill"))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(call.muted ? Color.isletRedText : Color.isletGreen)
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeOut(duration: 0.2), value: call.muted)
    }
}

/// The call's time since it connected, m:ss (or h:mm:ss).
struct CallTimer: View {
    let call: CallState
    var size: CGFloat = 13
    var weight: Font.Weight = .semibold
    var color: Color = .isletGreen

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.format(call.connectedAt.map { ctx.date.timeIntervalSince($0) }))
                .font(.system(size: size, weight: weight)).monospacedDigit().foregroundStyle(color)
        }
    }

    static func format(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "0:00" }
        let t = Int(max(seconds, 0))
        let h = t / 3600, m = (t / 60) % 60, s = t % 60
        return h > 0 ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))" : "\(m):\(String(format: "%02d", s))"
    }
}

/// The expanded panel's call page: who, how long, and FaceTime's Mute, Camera and End.
struct CallPage: View {
    let store: IslandStore

    var body: some View {
        let call = store.call ?? CallState(phase: .active)
        VStack(spacing: 0) {
            HStack {
                Text("FACETIME").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.isletTertiary)
                Spacer()
                Button { store.collapse() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.isletText)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.isletRing))
                }
                .buttonStyle(.plain).help("Collapse")
            }
            HStack(spacing: 16) {
                Circle().fill(Color(hex: 0x5E5CE6)).frame(width: 60, height: 60)
                    .overlay(Text(String(call.displayName.prefix(1))).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(call.displayName).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                    HStack(spacing: 0) {
                        CallTimer(call: call, size: 13, weight: .regular, color: .isletSecondary)
                        Text(" · \(call.kindLabel)").font(.system(size: 13)).foregroundStyle(Color.isletSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                control(call.muted ? "Muted" : "Mute", icon: call.muted ? "mic.slash.fill" : "mic.fill", on: call.muted) { store.callMute?() }
                control(call.cameraOn ? "Camera" : "Camera off", icon: call.cameraOn ? "video.fill" : "video.slash.fill", on: !call.cameraOn) {
                    store.callCamera?()
                }
                VStack(spacing: 5) {
                    Button { store.callEnd?() } label: {
                        Image(systemName: "phone.down.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(Circle().fill(Color.isletRed))
                    }
                    .buttonStyle(.plain).accessibilityLabel("End call")
                    Text("End").font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
                }
            }
        }
    }

    /// A round control: white with a black glyph while it's on (muted, camera off).
    private func control(_ label: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(on ? Color.black : Color.isletText)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 48, height: 48).background(Circle().fill(on ? Color.isletText : Color.isletRing))
            }
            .buttonStyle(.plain).accessibilityLabel(label)
            .animation(.easeOut(duration: 0.2), value: on)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.isletTertiary)
        }
    }
}
