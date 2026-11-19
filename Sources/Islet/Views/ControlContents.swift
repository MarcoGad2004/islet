import CoreGraphics
import SwiftUI

private let cardFill = Color(hex: 0x1C1C1E)

struct SettingsLink: View {
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

// MARK: - Source icon

/// The app that is playing the audio (Music, Spotify, a browser...), shown instead of the level bars.
struct SourceIcon: View {
    var bundleID: String
    var size: CGFloat
    var playing: Bool

    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        Group {
            if let icon = Self.icon(bundleID) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: size * 0.6)).foregroundStyle(Color.isletSecondary)
            }
        }
        .frame(width: size, height: size)
        .opacity(playing ? 1 : 0.45)
        .animation(.easeOut(duration: 0.3), value: playing)
    }

    @MainActor static func icon(_ id: String) -> NSImage? {
        if let c = cache[id] { return c }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[id] = img
        return img
    }
}

// MARK: - Display and sound

struct DisplayToggleRow: View {
    let display: DisplayToggles

    var body: some View {
        HStack(spacing: 10) {
            toggleTile("Dark Mode", icon: "circle.lefthalf.filled", on: display.darkMode) { display.setDarkMode(!display.darkMode) }
            if display.nightShiftSupported { toggleTile("Night Shift", icon: "sun.max.circle.fill", on: display.nightShift) { display.setNightShift(!display.nightShift) } }
            if display.trueToneSupported { toggleTile("True Tone", icon: "sun.dust.fill", on: display.trueTone) { display.setTrueTone(!display.trueTone) } }
        }
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

struct SoundOutputList: View {
    let levels: LevelsController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OUTPUT").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary)
                Spacer()
                SettingsLink(title: "Sound Settings…", pane: SystemSettings.sound)
            }.padding(.top, 8).padding(.bottom, 2)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(levels.devices) { d in
                        let icon = BluetoothController.icon(name: d.name, major: 0)
                        Button { levels.selectOutput(d) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: icon == "dot.radiowaves.left.and.right" ? "speaker.wave.2.fill" : icon)
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
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardFill))
    }
}

// MARK: - Wi-Fi

struct WiFiContent: View {
    let wifi: WiFiController
    @State private var asking: WiFiNetwork?
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwitchRow(title: "Wi-Fi", subtitle: Self.status(wifi), on: wifi.powerOn) { on in
                wifi.setPower(on)
                if on { Task { try? await Task.sleep(for: .seconds(2)); await wifi.scan() } }
            }.padding(.top, 8)
            Divider().overlay(Color(hex: 0x38383A))
            Group {
                if !wifi.powerOn { message("Turn Wi-Fi on to see networks.") }
                else if let net = asking { passwordPrompt(net) }
                else if !wifi.locationAllowed { locationPrompt }
                else { list }
            }.frame(maxHeight: .infinity)
            HStack {
                if let e = wifi.error { Text(e).font(.system(size: 11)).foregroundStyle(Color.isletRedText).lineLimit(1) }
                if wifi.scanning && !wifi.networks.isEmpty { ProgressView().controlSize(.mini) }
                Spacer()
                SettingsLink(title: "Wi-Fi Settings…", pane: SystemSettings.wifi)
            }.padding(.bottom, 6)
        }
        .padding(.horizontal, 12)
    }

    /// "Off", "Not connected", the network, or "Personal Hotspot · Marco's iPhone".
    static func status(_ wifi: WiFiController) -> String {
        guard wifi.powerOn else { return "Off" }
        guard let ssid = wifi.ssid else { return "Not connected" }
        return wifi.hotspot ? "Personal Hotspot · \(ssid)" : ssid
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

    /// Phones offering Instant Hotspot that aren't already in the scan (the phone isn't broadcasting yet).
    private var phones: [InstantHotspot] {
        let scanned = Set(wifi.networks.map(\.ssid))
        return wifi.instantHotspots.filter { !scanned.contains($0.name) }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                if wifi.scanning && wifi.networks.isEmpty && phones.isEmpty { ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 14) }
                ForEach(wifi.networks.filter { $0.ssid == wifi.ssid }) { n in row(n) }
                ForEach(phones) { h in
                    Button { Task { await wifi.join(h) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "personalhotspot").font(.system(size: 12)).frame(width: 20).foregroundStyle(Color.isletSecondary)
                            Text(h.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                            Spacer()
                            if wifi.joining == h.name { ProgressView().controlSize(.small) }
                            else { hotspotDetail(bars: h.bars, battery: h.battery) }
                        }
                        .frame(height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                ForEach(wifi.networks.filter { $0.ssid != wifi.ssid }) { n in row(n) }
            }
        }
    }

    /// One scanned network. The connected one (always first) gets a Disconnect button.
    @ViewBuilder private func row(_ n: WiFiNetwork) -> some View {
        let phone = wifi.instantHotspots.first { $0.name == n.ssid }
        let connected = n.ssid == wifi.ssid
        let connectedHotspot = connected && wifi.hotspot
        Button { tap(n) } label: {
            HStack(spacing: 10) {
                Group {
                    if connectedHotspot { Image(systemName: "personalhotspot").foregroundStyle(Color.isletGreen) }
                    else if n.hotspot || phone != nil { Image(systemName: "personalhotspot").foregroundStyle(Color.isletSecondary) }
                    else { Image(systemName: "wifi", variableValue: Double(n.bars) / 3).foregroundStyle(Color.isletSecondary) }
                }.font(.system(size: 12)).frame(width: 20)
                Text(n.ssid).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                if n.secured && phone == nil {
                    Image(systemName: n.enterprise ? "person.badge.key.fill" : "lock.fill").font(.system(size: 9)).foregroundStyle(Color.isletTertiary)
                }
                if connectedHotspot { Text("Hotspot").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.isletGreen) }
                Spacer()
                if wifi.joining == n.ssid { ProgressView().controlSize(.small) }
                else if connected {
                    Button("Disconnect") { Task { await wifi.disconnect() } }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.isletCyan)
                        .padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(Color(hex: 0x2C2C2E)))
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x0A84FF))
                }
                else if let phone { hotspotDetail(bars: phone.bars, battery: phone.battery) }
                else if n.known { Text("Saved").font(.system(size: 10)).foregroundStyle(Color.isletTertiary) }
            }
            .frame(height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    /// Cellular bars and a battery icon, as Wi-Fi Settings shows them for a phone. The phone only reports its battery
    /// in quarters, so it's an icon rather than a misleading percentage.
    private func hotspotDetail(bars: Int, battery: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cellularbars", variableValue: Double(bars) / 4)
            if let battery {
                Image(systemName: battery >= 100 ? "battery.100" : battery >= 75 ? "battery.75" : battery >= 50 ? "battery.50"
                      : battery >= 25 ? "battery.25" : "battery.0")
                    .font(.system(size: 12))
            }
        }
        .font(.system(size: 10)).foregroundStyle(Color.isletTertiary)
    }

    private func tap(_ n: WiFiNetwork) {
        guard n.ssid != wifi.ssid, wifi.joining == nil else { return }
        // A phone already broadcasting: let Instant Hotspot join it (no password needed).
        if let phone = wifi.instantHotspots.first(where: { $0.name == n.ssid }) { Task { await wifi.join(phone) }; return }
        if !n.secured || n.known {
            // A saved network joins with what macOS stored; ask only if that fails.
            Task {
                if await wifi.join(n, password: nil) == nil { await wifi.scan() }
                else if n.secured { ask(n) }
            }
        } else {
            ask(n)
        }
    }

    private func ask(_ n: WiFiNetwork) { asking = n; username = ""; password = ""; wifi.error = nil }

    private func passwordPrompt(_ n: WiFiNetwork) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(n.enterprise ? "Sign in to “\(n.ssid)”" : "Password for “\(n.ssid)”")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
            if n.enterprise {
                TextField("Username", text: $username).textFieldStyle(.roundedBorder).controlSize(.small)
                    .textContentType(.username).autocorrectionDisabled()
            }
            HStack {
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder).controlSize(.small)
                    .textContentType(.password).onSubmit { join(n) }
                Button("Join") { join(n) }.controlSize(.small).disabled(!ready(n) || wifi.joining != nil)
                Button("Cancel") { asking = nil; wifi.error = nil }.controlSize(.small)
            }
        }.frame(maxHeight: .infinity)
    }

    private func ready(_ n: WiFiNetwork) -> Bool { !password.isEmpty && (!n.enterprise || !username.isEmpty) }

    private func join(_ n: WiFiNetwork) {
        guard ready(n) else { return }
        let user = n.enterprise ? username : nil, pw = password
        Task {
            if await wifi.join(n, username: user, password: pw) == nil {
                asking = nil; username = ""; password = ""; await wifi.scan()
            }
        }
    }
}

// MARK: - Bluetooth

struct BluetoothContent: View {
    let bt: BluetoothController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwitchRow(title: "Bluetooth", subtitle: bt.powerOn ? "On" : "Off", on: bt.powerOn) { bt.setPower($0) }.padding(.top, 8)
            Divider().overlay(Color(hex: 0x38383A))
            Group {
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
            }.frame(maxHeight: .infinity)
            HStack {
                if let e = bt.error { Text(e).font(.system(size: 11)).foregroundStyle(Color.isletRedText).lineLimit(1) }
                Spacer()
                SettingsLink(title: "Bluetooth Settings…", pane: SystemSettings.bluetooth)
            }.padding(.bottom, 6)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Mirroring and Sidecar

struct MirroringContent: View {
    let sidecar: SidecarController?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MIRROR OR EXTEND TO").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.isletTertiary).padding(.top, 8)
            if let s = sidecar, !s.devices.isEmpty {
                ForEach(s.devices) { d in
                    Button { Task { await s.toggle(d) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "ipad").font(.system(size: 13)).frame(width: 20)
                                .foregroundStyle(d.connected ? Color(hex: 0x0A84FF) : Color.isletSecondary)
                            Text(d.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                            Spacer()
                            if s.busy == d.id { ProgressView().controlSize(.small) }
                            else { Text(d.connected ? "Connected" : "Sidecar").font(.system(size: 10)).foregroundStyle(Color.isletTertiary) }
                        }
                        .frame(height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            } else {
                Text("No iPad nearby. Make sure it's signed in to the same Apple Account with Bluetooth and Wi-Fi on.")
                    .font(.system(size: 11)).foregroundStyle(Color.isletSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if let e = sidecar?.error { Text(e).font(.system(size: 11)).foregroundStyle(Color.isletRedText).lineLimit(1) }
            Spacer(minLength: 0)
            HStack {
                Text("TVs and AirPlay displays: use Display Settings.").font(.system(size: 10)).foregroundStyle(Color.isletTertiary)
                Spacer()
                SettingsLink(title: "Display Settings…", pane: SystemSettings.displays)
            }.padding(.bottom, 6)
        }
        .padding(.horizontal, 12)
    }
}
