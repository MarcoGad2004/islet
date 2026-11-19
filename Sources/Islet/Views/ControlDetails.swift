import CoreGraphics
import SwiftUI

/// Detail views opened from the Control Center page. Each mimics what Control Center offers for that control and
/// falls back to a button that opens the matching System Settings pane.
struct ControlDetailView: View {
    let store: IslandStore
    let detail: ControlDetail

    var body: some View {
        switch detail {
        case .display: DisplayDetail(store: store)
        case .sound: SoundDetail(store: store)
        case .wifi: if let w = store.wifi { WiFiDetail(wifi: w) }
        case .bluetooth: if let b = store.bluetooth { BluetoothDetail(bt: b) }
        case .mirroring: MirroringDetail()
        }
    }
}

private let cardFill = Color(hex: 0x1C1C1E)

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardFill))
    }
}

private struct SettingsLink: View {
    var title: String
    var pane: String
    var body: some View {
        Button { SystemSettings.open(pane) } label: {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.isletCyan)
        }.buttonStyle(.plain)
    }
}

private struct SwitchRow: View {
    var title: String
    var subtitle: String
    var on: Bool
    var set: (Bool) -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.isletText)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.isletSecondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { on }, set: set)).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.green)
        }
    }
}

// MARK: - Display

private struct DisplayDetail: View {
    let store: IslandStore

    var body: some View {
        VStack(spacing: 10) {
            if let levels = store.levels {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.max.fill").font(.system(size: 15, weight: .semibold)).frame(width: 22)
                        ValueSlider(value: levels.brightness, height: 14, enabled: levels.brightnessAvailable, onChange: { levels.setBrightness($0) })
                        Text("\(Int((levels.brightness * 100).rounded()))%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }.foregroundStyle(Color.isletText)
                }.frame(height: 56)
            }
            if let d = store.display {
                HStack(spacing: 10) {
                    toggleTile("Dark Mode", icon: "circle.lefthalf.filled", on: d.darkMode) { d.setDarkMode(!d.darkMode) }
                    if d.nightShiftSupported { toggleTile("Night Shift", icon: "sun.max.circle.fill", on: d.nightShift) { d.setNightShift(!d.nightShift) } }
                    if d.trueToneSupported { toggleTile("True Tone", icon: "sun.dust.fill", on: d.trueTone) { d.setTrueTone(!d.trueTone) } }
                }
                .frame(height: 62)
            }
            Spacer(minLength: 0)
        }
        .onAppear { store.display?.refresh() }
    }

    private func toggleTile(_ title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(on ? Color(hex: 0x0A84FF) : Color(hex: 0x3A3A3C))
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }.frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                    Text(on ? "On" : "Off").font(.system(size: 11)).foregroundStyle(Color.isletSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardFill))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }
}

// MARK: - Sound

private struct SoundDetail: View {
    let store: IslandStore

    var body: some View {
        if let levels = store.levels {
            VStack(spacing: 10) {
                Card {
                    HStack(spacing: 12) {
                        Button { levels.toggleMute() } label: {
                            Image(systemName: levels.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 15, weight: .semibold)).frame(width: 22)
                        }.buttonStyle(.plain)
                        ValueSlider(value: levels.muted ? 0 : levels.volume, height: 14, onChange: { levels.setVolume($0) })
                        Text("\(Int(((levels.muted ? 0 : levels.volume) * 100).rounded()))%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }.foregroundStyle(Color.isletText)
                }.frame(height: 56)
                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("OUTPUT").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary)
                            Spacer()
                            SettingsLink(title: "Sound Settings…", pane: SystemSettings.sound)
                        }.padding(.top, 8).padding(.bottom, 2)
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(levels.devices) { d in
                                    Button { levels.selectOutput(d) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: BluetoothController.icon(name: d.name, major: 0) == "dot.radiowaves.left.and.right" ? "speaker.wave.2.fill" : BluetoothController.icon(name: d.name, major: 0))
                                                .font(.system(size: 12)).frame(width: 20).foregroundStyle(Color.isletSecondary)
                                            Text(d.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                                            Spacer()
                                            if d.name == levels.outputName { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x0A84FF)) }
                                        }
                                        .frame(height: 28).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .onAppear { levels.refresh() }
        }
    }
}

// MARK: - Wi-Fi

private struct WiFiDetail: View {
    let wifi: WiFiController
    @State private var asking: WiFiNetwork?
    @State private var password = ""

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SwitchRow(title: "Wi-Fi", subtitle: wifi.powerOn ? (wifi.ssid ?? "Not connected") : "Off", on: wifi.powerOn) { on in
                    wifi.setPower(on)
                    if on { Task { try? await Task.sleep(for: .seconds(2)); await wifi.scan() } }
                }.padding(.top, 8)
                Divider().overlay(Color(hex: 0x38383A))
                if !wifi.powerOn {
                    message("Turn Wi-Fi on to see networks.")
                } else if let net = asking {
                    passwordPrompt(net)
                } else if !wifi.locationAllowed {
                    locationPrompt
                } else {
                    list
                }
                Spacer(minLength: 0)
                HStack {
                    if let e = wifi.error { Text(e).font(.system(size: 11)).foregroundStyle(Color.isletRedText).lineLimit(1) }
                    if wifi.scanning && !wifi.networks.isEmpty { ProgressView().controlSize(.mini) }
                    Spacer()
                    SettingsLink(title: "Wi-Fi Settings…", pane: SystemSettings.wifi)
                }.padding(.bottom, 6)
            }
        }
        .task { wifi.refresh(); await wifi.scan() }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color.isletSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var locationPrompt: some View {
        VStack(spacing: 6) {
            Text("Network names need Location access.").font(.system(size: 12)).foregroundStyle(Color.isletSecondary)
            Button(wifi.locationStatus == .notDetermined ? "Allow Location…" : "Open Location Settings…") {
                if wifi.locationStatus == .notDetermined { wifi.requestLocation() } else { SystemSettings.open(SystemSettings.location) }
            }.controlSize(.small)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                if wifi.scanning && wifi.networks.isEmpty { ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 14) }
                ForEach(wifi.networks) { n in
                    Button { tap(n) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi", variableValue: Double(n.bars) / 3).font(.system(size: 12)).frame(width: 20).foregroundStyle(Color.isletSecondary)
                            Text(n.ssid).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                            if n.secured { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Color.isletTertiary) }
                            Spacer()
                            if wifi.joining == n.ssid { ProgressView().controlSize(.small) }
                            else if n.ssid == wifi.ssid { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x0A84FF)) }
                            else if n.known { Text("Saved").font(.system(size: 10)).foregroundStyle(Color.isletTertiary) }
                        }
                        .frame(height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func tap(_ n: WiFiNetwork) {
        guard n.ssid != wifi.ssid, wifi.joining == nil else { return }
        if n.secured { asking = n; password = "" }
        else { Task { _ = await wifi.join(n, password: nil); await wifi.scan() } }
    }

    private func passwordPrompt(_ n: WiFiNetwork) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password for “\(n.ssid)”").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
            HStack {
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder).controlSize(.small)
                    .onSubmit { join(n) }
                Button("Join") { join(n) }.controlSize(.small).disabled(password.isEmpty || wifi.joining != nil)
                Button("Cancel") { asking = nil; wifi.error = nil }.controlSize(.small)
            }
        }.frame(maxHeight: .infinity)
    }

    private func join(_ n: WiFiNetwork) {
        let pw = password
        Task {
            if await wifi.join(n, password: pw) == nil { asking = nil; password = ""; await wifi.scan() }
        }
    }
}

// MARK: - Bluetooth

private struct BluetoothDetail: View {
    let bt: BluetoothController

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SwitchRow(title: "Bluetooth", subtitle: bt.powerOn ? "On" : "Off", on: bt.powerOn) { bt.setPower($0) }.padding(.top, 8)
                Divider().overlay(Color(hex: 0x38383A))
                if !bt.powerOn {
                    Text("Turn Bluetooth on to see your devices.").font(.system(size: 12)).foregroundStyle(Color.isletSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(bt.devices) { d in
                                Button { Task { await bt.toggle(d) } } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: d.icon).font(.system(size: 12)).frame(width: 20)
                                            .foregroundStyle(d.connected ? Color(hex: 0x0A84FF) : Color.isletSecondary)
                                        Text(d.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                                        Spacer()
                                        if bt.busy.contains(d.id) { ProgressView().controlSize(.small) }
                                        else { Text(d.connected ? "Connected" : "Not connected").font(.system(size: 10)).foregroundStyle(d.connected ? Color.isletSecondary : Color.isletTertiary) }
                                    }
                                    .frame(height: 26).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    if let e = bt.error { Text(e).font(.system(size: 11)).foregroundStyle(Color.isletRedText).lineLimit(1) }
                    Spacer()
                    SettingsLink(title: "Bluetooth Settings…", pane: SystemSettings.bluetooth)
                }.padding(.bottom, 6)
            }
        }
        .onAppear { bt.refresh() }
    }
}

// MARK: - Mirroring

private struct MirroringDetail: View {
    private var screens: [NSScreen] { NSScreen.screens }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("DISPLAYS").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary).padding(.top, 8)
                ForEach(screens, id: \.self) { s in
                    HStack(spacing: 10) {
                        Image(systemName: s.safeAreaInsets.top > 0 ? "laptopcomputer" : "display").font(.system(size: 12)).frame(width: 20).foregroundStyle(Color.isletSecondary)
                        Text(s.localizedName).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                        Spacer()
                    }.frame(height: 24)
                }
                Text("Choose an AirPlay display or mirror this screen in Display Settings.")
                    .font(.system(size: 11)).foregroundStyle(Color.isletSecondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack { Spacer(); SettingsLink(title: "Display Settings…", pane: SystemSettings.displays) }.padding(.bottom, 6)
            }
        }
    }
}
