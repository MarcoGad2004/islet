import AVFoundation
import CoreLocation
import ServiceManagement
import SwiftUI

/// Welcome → permissions → optional face unlock → done. Every permission is explained and can be granted here.
struct OnboardingView: View {
    let face: FaceUnlockCoordinator
    let levels: LevelsController
    let media: MediaMonitor
    let focus: FocusMonitor
    let wifi: WiFiController
    var finish: () -> Void

    private enum Step: Int, CaseIterable { case welcome, permissions, face, done }
    private enum FaceStep { case intro, password, scanning, enrolled }

    @State private var step = Step.welcome
    @State private var faceStep = FaceStep.intro
    @State private var accessibility = AXIsProcessTrusted()
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var password = ""
    @State private var message: String?
    @State private var busy = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: welcome
                case .permissions: permissions
                case .face: faceSetup
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36).padding(.top, 32)
            Divider()
            footer
        }
        .frame(width: 520, height: 700)
        .onReceive(tick) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: face.enrolment?.phase) { _, phase in
            if faceStep == .scanning, let phase, phase != .scanning {
                if phase == .success { face.unlock.enabled = true; faceStep = .enrolled; message = nil }
                else if case .failed(let m) = phase { message = m; faceStep = .intro }
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text("Welcome to Islet").font(.largeTitle.weight(.semibold))
            Text("Islet turns your MacBook's notch into a live island: now playing, charging, volume and brightness, and an optional face unlock for the lock screen.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Setup takes about a minute.").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Permissions", "Islet asks for as little as it can. Everything stays on this Mac.")
            card {
                permission("Accessibility", icon: "accessibility", ok: accessibility,
                           detail: "Lets Islet read the menu bar's width, catch the volume and brightness keys, and type your password at the lock screen.",
                           action: accessibilityAction)
                Divider()
                permission("Camera", icon: "camera.fill", ok: camera == .authorized,
                           detail: "Only used for face unlock, and only while you set it up or the Mac is locked.",
                           action: cameraAction)
                Divider()
                permission("Location", icon: "location.fill", ok: wifi.locationAllowed,
                           detail: "Only so macOS lets Islet read the names of nearby Wi-Fi networks. Your location is never used.",
                           action: locationAction)
                Divider()
                permission("Full Disk Access", icon: "internaldrive.fill", ok: focus.accessGranted,
                           detail: "Only to see which Focus is on. Islet reads it and never changes it. Restart Islet after allowing.",
                           action: { SystemSettings.open(SystemSettings.fullDisk) })
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform").frame(width: 22).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now playing")
                        Text(media.available ? "Working. Needs no permission." : "Unavailable on this Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    status(media.available)
                }
            }
            if !accessibility {
                Text("After you switch Islet on in System Settings, come back here. This page updates by itself.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !levels.tapActive {
                Text("Volume and brightness keys will start working after Islet restarts.").font(.caption).foregroundStyle(.secondary)
            }
            card {
                Toggle("Open Islet when I log in", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                Divider()
                Toggle("Show a menu bar icon", isOn: $showMenuBarIcon)
                Text("Without it, open settings from the gear in the expanded notch.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var faceSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Face unlock", "Optional. Unlock this Mac's lock screen by looking at it.")
            switch faceStep {
            case .intro:
                card {
                    bullet("lock.open.fill", "After a face match, Islet types your login password into the lock screen for you.")
                    bullet("key.fill", "Your password is checked, then stored only in this Mac's Keychain.")
                    bullet("exclamationmark.shield.fill", "Convenient, but weaker than Touch ID. A good enough likeness could fool it.")
                }
                if !face.modelAvailable {
                    Text("The face model isn't installed in this build, so face unlock can't be set up.").foregroundStyle(.orange)
                }
                if !accessibility {
                    Text("Face unlock needs Accessibility (previous step) to type the password.").font(.callout).foregroundStyle(.orange)
                }
                Button("Set up face unlock") { Task { await begin() } }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy || !face.modelAvailable)
            case .password:
                Text("Enter your Mac login password. It is verified against your account first.").foregroundStyle(.secondary)
                SecureField("Login password", text: $password).textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await savePassword() } }
                HStack {
                    Button("Save and continue") { Task { await savePassword() } }
                        .buttonStyle(.borderedProminent).disabled(password.isEmpty || busy)
                    Button("Back") { password = ""; message = nil; faceStep = .intro }
                }
            case .scanning:
                card {
                    HStack(spacing: 14) {
                        ProgressView()
                        Text("Look at the notch and slowly move your head in a circle, keeping the dot on the ring.")
                    }
                }
                Text("The scan plays in the notch at the top of your screen.").font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { face.cancelEnrolment(); faceStep = .intro }
            case .enrolled:
                card {
                    Label("Face enrolled and face unlock is on.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Lock your Mac to try it. You can test it, tune it or remove it in Settings.").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let message { Text(message).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("You're set").font(.largeTitle.weight(.semibold))
            card {
                bullet("cursorarrow.motionlines", "Hover the notch and it bubbles out. Click it to open the controls.")
                bullet("gearshape.fill", "The gear in the open notch is Settings: updates, face unlock and more.")
                bullet("hand.draw.fill", "Swipe up over the notch with two fingers to hide it, down to bring it back.")
                bullet("switch.2", "The notch now has Wi-Fi, Bluetooth, AirDrop, volume and brightness. To use it instead of Control Center, hide that icon in System Settings.")
                Button("Open Control Center settings…") { SystemSettings.open(SystemSettings.controlCenter) }.controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Pieces

    private var footer: some View {
        HStack {
            if step != .welcome && faceStep != .scanning {
                Button("Back") { go(-1) }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle().fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                }
            }
            Spacer()
            switch step {
            case .welcome: Button("Get started") { go(1) }.buttonStyle(.borderedProminent)
            case .permissions: Button("Continue") { go(1) }.buttonStyle(.borderedProminent)
            case .face:
                Button(faceStep == .enrolled ? "Continue" : "Skip for now") { go(1) }
                    .buttonStyle(.borderedProminent).disabled(faceStep == .scanning || busy)
            case .done: Button("Finish") { finish() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Color.accentColor)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func status(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? .green : .secondary).font(.title3)
    }

    private func permission(_ title: String, icon: String, ok: Bool, detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if ok { status(true) } else { Button("Allow…", action: action) }
        }
    }

    // MARK: Actions

    private func go(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next; message = nil }
    }

    private func refresh() {
        face.unlock.refreshPermission()
        accessibility = AXIsProcessTrusted()
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        wifi.refresh()
        focus.retry()
        if accessibility { levels.retryTap() }
    }

    private func accessibilityAction() {
        face.unlock.requestPermission()
        open("Privacy_Accessibility")
    }

    private func locationAction() {
        if wifi.locationStatus == .notDetermined { wifi.requestLocation() } else { SystemSettings.open(SystemSettings.location) }
    }

    private func cameraAction() {
        if camera == .notDetermined {
            Task { _ = await FaceCamera.requestAccess(); refresh() }
        } else {
            open("Privacy_Camera")
        }
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {
            message = "Couldn't change launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func begin() async {
        message = nil
        busy = true; defer { busy = false }
        guard await IdentityCheck.confirmOwner(reason: "Set up face unlock for this Mac") else {
            message = "Identity wasn't confirmed."; return
        }
        if face.faces.hasPassword { await startScan() } else { faceStep = .password }
    }

    private func savePassword() async {
        busy = true; defer { busy = false }
        guard IdentityCheck.verifyLoginPassword(password) else { message = "That isn't your login password."; return }
        guard face.faces.savePassword(password) else { message = "Couldn't save to the Keychain."; return }
        password = ""; message = nil
        face.unlock.clearPasswordRejected()
        await startScan()
    }

    private func startScan() async {
        if let error = await face.beginEnrolment() { message = error; faceStep = .intro } else { faceStep = .scanning }
    }
}
