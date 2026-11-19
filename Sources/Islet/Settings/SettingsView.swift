import ServiceManagement
import SwiftUI

/// Settings. For now: face unlock setup (M8 builds the unlock itself). Launch at login and permissions
/// status arrive with M9.
struct SettingsView: View {
    let face: FaceUnlockCoordinator
    let levels: LevelsController
    let media: MediaMonitor
    let focus: FocusMonitor
    let wifi: WiFiController
    var runSetup: () -> Void = {}
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var updater = Updater()

    private enum Step { case overview, password, scanning }
    @State private var step = Step.overview
    @State private var password = ""
    @State private var message: String?
    @State private var busy = false
    @State private var confirmRemove = false

    var body: some View {
        ScrollView { content }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General").font(.title2.weight(.semibold))
            Toggle("Open Islet at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            if !showMenuBarIcon {
                Text("Open settings from the gear in the expanded notch (click the notch).").font(.caption).foregroundStyle(.secondary)
            }
            permissionRow("Accessibility", ok: face.unlock.accessibilityTrusted,
                          detail: "Menu bar width check, volume and brightness keys, typing the password") { face.unlock.requestPermission() }
            permissionRow("Volume and brightness keys", ok: levels.tapActive, detail: "Needs Accessibility; restart Islet after allowing", action: nil)
            permissionRow("Location (Wi-Fi network names)", ok: wifi.locationAllowed, detail: "Lets Islet list nearby Wi-Fi networks") {
                if wifi.locationStatus == .notDetermined { wifi.requestLocation() } else { SystemSettings.open(SystemSettings.location) }
            }
            permissionRow("Full Disk Access (Focus)", ok: focus.accessGranted, detail: "Lets Islet see which Focus is on; restart Islet after allowing") {
                SystemSettings.open(SystemSettings.fullDisk)
            }
            permissionRow("Now playing", ok: media.available, detail: media.available ? "Working" : "Adapter unavailable", action: nil)
            Divider().padding(.top, 4)
            updates
            Divider().padding(.top, 4)
        }
        .onAppear { face.unlock.refreshPermission(); levels.retryTap(); wifi.refresh(); focus.retry() }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Updates").font(.title2.weight(.semibold))
            HStack {
                Text("Version \(updater.currentVersion)")
                Spacer()
                switch updater.state {
                case .idle, .upToDate, .failed: Button("Check for updates") { updater.check() }
                case .checking: ProgressView().controlSize(.small)
                case .available(let tag): Button("Install \(tag) and restart") { updater.install(tag) }.buttonStyle(.borderedProminent)
                case .downloading: ProgressView().controlSize(.small)
                }
            }
            switch updater.state {
            case .upToDate: Text("You're up to date.").font(.caption).foregroundStyle(.secondary)
            case .failed(let m): Text(m).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            case .downloading: Text("Downloading, Islet will restart…").font(.caption).foregroundStyle(.secondary)
            default: EmptyView()
            }
            HStack {
                Button("Run setup again…") { runSetup() }
                Button("Quit Islet") { NSApp.terminate(nil) }
            }.padding(.top, 4)
        }
    }

    private func permissionRow(_ title: String, ok: Bool, detail: String, action: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !ok, let action { Button("Allow…", action: action) }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {
            message = "Couldn't change launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            general
            Text("Face unlock").font(.title2.weight(.semibold))
            Text("Unlocks this Mac's lock screen with the camera. It is convenient, not as strong as Touch ID, and only ever types your login password into the lock screen.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            statusRows
            unlockControls

            switch step {
            case .overview: overview
            case .password: passwordStep
            case .scanning: scanningStep
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            testSection
            if face.faces.isEnrolled {
                Divider()
                protectionSection
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 460, alignment: .topLeading)
        .onChange(of: face.enrolment?.phase) { _, phase in
            if step == .scanning, phase != nil, phase != .scanning { step = .overview }
        }
        .confirmationDialog("Remove face unlock?", isPresented: $confirmRemove) {
            Button("Remove face and password", role: .destructive) { face.stopTest(); face.faces.removeAll() }
        } message: { Text("Deletes the stored face data and login password from the Keychain.") }
    }

    // MARK: Pieces

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Face model", ok: face.modelAvailable, detail: face.modelAvailable ? "Installed" : "Missing (run scripts/fetch-model.sh)")
            row("Face", ok: face.faces.isEnrolled, detail: face.faces.isEnrolled ? "Enrolled" : "Not set up")
            row("Login password", ok: face.faces.hasPassword, detail: face.faces.hasPassword ? "Stored in the Keychain" : "Not stored")
        }
    }

    private func row(_ title: String, ok: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? .green : .secondary)
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private var unlockControls: some View {
        let unlock = face.unlock
        return VStack(alignment: .leading, spacing: 8) {
            Toggle("Unlock this Mac's lock screen with my face", isOn: Binding(get: { unlock.enabled }, set: { unlock.enabled = $0 }))
            HStack {
                Image(systemName: unlock.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(unlock.accessibilityTrusted ? .green : .orange)
                Text(unlock.accessibilityTrusted ? "Accessibility allowed (needed to type the password)" : "Accessibility is off: needed to type the password")
                    .font(.callout)
                Spacer()
                if !unlock.accessibilityTrusted { Button("Allow…") { unlock.requestPermission() } }
            }
            if unlock.passwordRejected {
                HStack {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text("The stored password wasn't accepted, so face unlock is paused. Change the password to resume.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { unlock.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in unlock.refreshPermission() }
    }

    private var overview: some View {
        HStack {
            Button(face.faces.isReady ? "Scan face again…" : "Set up face unlock…") { Task { await begin() } }
                .buttonStyle(.borderedProminent).disabled(busy || !face.modelAvailable)
            if face.faces.hasPassword {
                Button("Change password…") { Task { await begin(passwordOnly: true) } }.disabled(busy)
            }
            Spacer()
            if face.faces.isEnrolled || face.faces.hasPassword {
                Button("Remove…", role: .destructive) { confirmRemove = true }
            }
        }
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter your Mac login password. It is checked against your account, then stored only in this Mac's Keychain.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField("Login password", text: $password).textFieldStyle(.roundedBorder)
                .onSubmit { Task { await savePassword() } }
            HStack {
                Button("Save") { Task { await savePassword() } }
                    .buttonStyle(.borderedProminent).disabled(password.isEmpty || busy)
                Button("Cancel") { password = ""; message = nil; step = .overview }
            }
        }
    }

    private var scanningStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Look at the notch at the top of your screen and slowly move your head in a circle. Keep the dot touching the ring all the way round.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Button("Cancel") { face.cancelEnrolment(); step = .overview }
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test recognition").font(.headline)
            HStack {
                Button(face.testingFace ? "Stop" : "Start test") {
                    Task {
                        if face.testingFace { face.stopTest() } else { message = await face.startTest() }
                    }
                }.disabled(!face.faces.isEnrolled || face.isEnrolling)
                if face.testingFace {
                    if let score = face.testScore {
                        let match = score >= face.faces.threshold && !face.testFramed
                        Label(String(format: "%.2f  %@", score, face.testFramed ? "Photo edge" : match ? "Match" : "No match"),
                              systemImage: match ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(match ? .green : .red).monospacedDigit()
                    } else {
                        Text("No face in view").foregroundStyle(.secondary)
                    }
                }
            }
            if face.testingFace {
                HStack(spacing: 16) {
                    Label(face.testBlinked ? "Blink seen" : "Blink once", systemImage: face.testBlinked ? "eye.fill" : "eye")
                        .foregroundStyle(face.testBlinked ? .green : .secondary)
                    if let light = face.testLight {
                        Label(String(format: "Light %.2f%@", light, light < 0.25 ? " (dark)" : ""), systemImage: "sun.min")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.callout)
            }
            HStack {
                Text("Match threshold").foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(face.faces.threshold) }, set: { face.faces.threshold = Float($0) }),
                       in: 0.25...0.75)
                Text(String(format: "%.2f", face.faces.threshold)).monospacedDigit().frame(width: 40)
            }
            Text("Try your face, then someone else's. Set the threshold between the two scores. Hold up a photo of yourself: it should say Photo edge, or never see a blink.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var protectionSection: some View {
        let faces = face.faces
        return VStack(alignment: .leading, spacing: 8) {
            Text("Protection and learning").font(.headline)
            Toggle("Require a blink (stops a still photo)", isOn: Binding(get: { faces.requireBlink }, set: { faces.requireBlink = $0 }))
            Toggle("Brighten the screen to light my face in the dark", isOn: Binding(get: { faces.brightenInDark }, set: { faces.brightenInDark = $0 }))
            Toggle("Learn from successful unlocks", isOn: Binding(get: { faces.learnFromUnlocks }, set: { faces.learnFromUnlocks = $0 }))
            HStack {
                Text(faces.learned.isEmpty ? "No looks learned yet" : "\(faces.learned.count) of \(FaceStore.maxLearned) looks learned")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if !faces.learned.isEmpty { Button("Forget learned looks") { faces.forgetLearned() } }
            }
            Text("A photo or phone held up to the camera is always refused. Learning only keeps unlocks that included a blink and matched your original scan well, so it adapts to new light, glasses or a haircut without drifting.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private func begin(passwordOnly: Bool = false) async {
        message = nil
        busy = true; defer { busy = false }
        face.stopTest()
        guard await IdentityCheck.confirmOwner(reason: "Set up face unlock for this Mac") else {
            message = "Identity wasn't confirmed."; return
        }
        if passwordOnly || !face.faces.hasPassword {
            step = .password
        } else {
            await startScan()
        }
    }

    private func savePassword() async {
        busy = true; defer { busy = false }
        guard IdentityCheck.verifyLoginPassword(password) else { message = "That isn't your login password."; return }
        guard face.faces.savePassword(password) else { message = "Couldn't save to the Keychain."; return }
        password = ""; message = nil
        face.unlock.clearPasswordRejected()
        if face.faces.isEnrolled { step = .overview } else { await startScan() }
    }

    private func startScan() async {
        if let error = await face.beginEnrolment() { message = error; step = .overview } else { step = .scanning }
    }
}
