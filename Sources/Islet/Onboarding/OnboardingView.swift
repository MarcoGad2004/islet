import AVFoundation
import CoreLocation
import ServiceManagement
import SwiftUI

/// Welcome → your Mac → what you want → what that needs → search's shortcut → Face Unlock → done (DESIGN.md "Setup").
/// Islet only asks for the permissions of the features picked; search and Face Unlock steps show only when picked.
struct OnboardingView: View {
    let face: FaceUnlockCoordinator
    let levels: LevelsController
    let media: MediaMonitor
    let focus: FocusMonitor
    let wifi: WiFiController
    var finish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, display, choose, permissions, search, face, done
        /// `-IsletDebugShape setup -IsletDebugStep choose` opens setup on that step.
        static var first: Step {
            #if DEBUG
            let names = ["welcome", "display", "choose", "permissions", "search", "face", "done"]
            if let n = UserDefaults.standard.string(forKey: "IsletDebugStep"), let i = names.firstIndex(of: n) { return Step(rawValue: i)! }
            #endif
            return .welcome
        }
    }
    private enum FaceStep { case intro, password, scanning, enrolled }

    @State private var step = Step.first
    @State private var faceStep = FaceStep.intro
    @State private var accessibility = AXIsProcessTrusted()
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var messagesAccess = MessagesAccess()
    @State private var spotlightConflict = SearchShortcut.spotlightConflict
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage(SearchShortcutChoice.key) private var searchShortcut = SearchShortcutChoice.commandSpace.rawValue
    /// What's ticked on the choose step. Face Unlock is turned on only once it's set up, so it's kept here till then.
    @State private var picked: Set<Feature> = Set(Feature.allCases.filter { $0 != .faceUnlock && $0.isOn })
    @State private var wantsFace = UserDefaults.standard.bool(forKey: "faceUnlockEnabled")
    @State private var password = ""
    @State private var message: String?
    @State private var busy = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: welcome
                case .display: display
                case .choose: choose
                case .permissions: permissions
                case .search: searchStep
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
            Text("Islet turns your MacBook's notch into a live island. Pick what you want it to do, and it only asks for what that needs.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Setup takes about a minute.").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Your Mac", "Islet lives in the notch. On a Mac without one it can bubble out of the top edge instead.")
            card { NotchChoice() }
            Spacer(minLength: 0)
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("What should Islet do?", "Pick what you want. You can change it any time in Settings, and Islet only asks for what the ticked ones need.")
            card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.square.fill").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The island").fontWeight(.semibold)
                        Text("Now playing, charging and battery, and Wi-Fi, Bluetooth and AirDrop in the open panel. Always on, needs nothing.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(Feature.allCases) { f in
                    Divider()
                    pickRow(f)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func isPicked(_ f: Feature) -> Bool {
        if f == .faceUnlock { return wantsFace }
        return picked.contains(f) && (f.parent.map { picked.contains($0) } ?? true)
    }

    private func pickRow(_ f: Feature) -> some View {
        let parentOff = f.parent.map { !picked.contains($0) } ?? false
        return Toggle(isOn: Binding(get: { isPicked(f) }, set: { pick(f, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).fontWeight(.semibold)
                Text(f.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(f.needs.isEmpty ? "Needs nothing" : "Needs " + SettingsChecks.list(f.needs))
                    .font(.caption2.weight(.medium)).foregroundStyle(f.needs.isEmpty ? Color.green : .secondary)
            }
            .padding(.leading, 4)
        }
        .toggleStyle(.checkbox)
        .disabled(parentOff)
        .padding(.leading, f.parent == nil ? 0 : 24)
    }

    private func pick(_ f: Feature, _ on: Bool) {
        if f == .faceUnlock { wantsFace = on; if !on { face.unlock.enabled = false }; return }
        if on { picked.insert(f) } else { picked.remove(f) }
        f.set(on)
        if f == .search { searchShortcut = SearchShortcutChoice.current.rawValue }
    }

    /// The picked features that need something, each with what it needs.
    private var neededGroups: [(Feature, [String])] {
        Feature.allCases.filter(isPicked).compactMap { f in f.needs.isEmpty ? nil : (f, f.needs) }
    }

    private var permissions: some View {
        let groups = neededGroups
        let missing = Set(groups.flatMap(\.1).filter { !permissionAllowed($0) })
        return VStack(alignment: .leading, spacing: 14) {
            header(groups.isEmpty ? "Nothing to allow" : missing.isEmpty ? "Everything you picked is ready" : "Allow what you picked",
                   groups.isEmpty ? "What you picked doesn't need any permissions." : "Only what your features need. Each one ticks itself off once it's allowed. Everything stays on this Mac.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !groups.isEmpty {
                        card {
                            ForEach(Array(neededNames.enumerated()), id: \.offset) { j, name in
                                if j > 0 { Divider() }
                                let users = groups.filter { $0.1.contains(name) }.map(\.0.title)
                                permission(name, icon: permissionIcon(name), ok: permissionAllowed(name),
                                           detail: "For " + SettingsChecks.list(users) + ". " + permissionHow(name), action: permissionAction(name))
                            }
                        }
                    }
                    let extras = optionalPermissions
                    if !extras.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Optional").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            card {
                                ForEach(Array(extras.enumerated()), id: \.offset) { j, e in
                                    if j > 0 { Divider() }
                                    permission(e.0, icon: permissionIcon(e.0), ok: false, detail: e.1 + " Fine without it.",
                                               action: { permissionAction(e.0)() })
                                }
                            }
                        }
                    }
                }
            }
            if missing.contains("Accessibility") {
                Text("After you switch Islet on in System Settings, come back here. This page updates by itself.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if isPicked(.levels), !levels.tapActive, accessibility {
                Text("Volume and brightness keys start working after Islet restarts.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Each needed permission once, in the order features list them.
    private var neededNames: [String] {
        var out: [String] = []
        for (_, names) in neededGroups { for n in names where !out.contains(n) { out.append(n) } }
        return out
    }

    /// Permissions nothing picked needs, but that add something to what was picked.
    private var optionalPermissions: [(String, String)] {
        let needed = Set(neededGroups.flatMap(\.1))
        var out: [(String, String)] = []
        if !wifi.locationAllowed { out.append(("Location", "The island: names of nearby Wi-Fi networks. Your location is never used.")) }
        if !needed.contains("Contacts"), !messagesAccess.contactsAllowed, isPicked(.notifications) || isPicked(.search) {
            out.append(("Contacts", "Names instead of numbers on notifications, and people in search."))
        }
        if !needed.contains("Accessibility"), !accessibility {
            out.append(("Accessibility", isPicked(.search) ? "Search: hand questions to Siri. The island: the wider layout when the menu bar has room."
                                                           : "The island: the wider layout when the menu bar has room."))
        }
        return out
    }

    private func permissionAllowed(_ name: String) -> Bool {
        switch name {
        case "Accessibility": accessibility
        case "Full Disk Access": focus.accessGranted
        case "Contacts": messagesAccess.contactsAllowed
        case "Control Messages": messagesAccess.automationAllowed
        case "Location": wifi.locationAllowed
        default: camera == .authorized
        }
    }

    private func permissionIcon(_ name: String) -> String {
        switch name {
        case "Accessibility": "accessibility"
        case "Full Disk Access": "internaldrive.fill"
        case "Contacts": "person.crop.circle.fill"
        case "Control Messages": "message.fill"
        case "Location": "location.fill"
        default: "camera.fill"
        }
    }

    private func permissionHow(_ name: String) -> String {
        switch name {
        case "Accessibility": "Opens System Settings: switch Islet on, then come back."
        case "Full Disk Access": "Opens System Settings: switch Islet on. Islet only reads Focus and Messages, never changes them. Restart Islet after."
        case "Contacts": "macOS asks right here."
        case "Control Messages": "Messages opens in the background and macOS asks."
        case "Location": "macOS asks right here. Your location is never used."
        default: "macOS asks right here. Only used while you set up Face Unlock or the Mac is locked."
        }
    }

    private func permissionAction(_ name: String) -> () -> Void {
        switch name {
        case "Accessibility": accessibilityAction
        case "Full Disk Access": { SystemSettings.open(SystemSettings.fullDisk) }
        case "Contacts": { messagesAccess.requestContacts() }
        case "Control Messages": { messagesAccess.requestAutomation() }
        case "Location": locationAction
        default: cameraAction
        }
    }

    private var searchStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("How should search open?", "Spotlight, and Siri inside it, use ⌘Space. Islet can take it over, or leave it and use another shortcut.")
            Form {
                Section { SearchShortcutChooser(shortcut: $searchShortcut) }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 190)
            .padding(.horizontal, -20)
            Text("To ask Siri, type “siri” and your question in Islet's search, or just a question. Return opens Spotlight with it asked.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        let checks = SettingsChecks(face: face, levels: levels, media: media, focus: focus, wifi: wifi, messagesAccess: messagesAccess,
                                    camera: camera, spotlightConflict: spotlightConflict, requestCamera: cameraAction)
        let on = Feature.allCases.filter { $0 == .faceUnlock ? face.unlock.enabled : $0.isOn }
        return VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("You're set").font(.largeTitle.weight(.semibold))
            card {
                ForEach(Array(on.enumerated()), id: \.offset) { i, f in
                    if i > 0 { Divider() }
                    let st = checks.state(f)
                    HStack {
                        Text(f.title)
                        Spacer()
                        if let ok = st.ok { Circle().fill(ok ? Color.green : .orange).frame(width: 7, height: 7) }
                        Text(st.text).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if on.isEmpty { Text("Just the island: now playing, charging and the controls.").foregroundStyle(.secondary) }
            }
            card {
                Toggle("Open Islet when I log in", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                Divider()
                Toggle("Show a menu bar icon", isOn: $showMenuBarIcon)
            }
            Text("Hover the notch and it bubbles out; click it for the panel, and the gear there for Settings. Anything still missing waits on Settings' Islet page.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                ForEach(steps, id: \.rawValue) { s in
                    Circle().fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                }
            }
            Spacer()
            switch step {
            case .welcome: Button("Get started") { go(1) }.buttonStyle(.borderedProminent)
            case .display, .choose, .search: Button("Continue") { go(1) }.buttonStyle(.borderedProminent)
            case .permissions:
                Button(neededGroups.flatMap(\.1).allSatisfy(permissionAllowed) ? "Continue" : "Skip for now") { go(1) }
                    .buttonStyle(.borderedProminent)
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

    /// The steps shown: search's and Face Unlock's only when they were picked.
    private var steps: [Step] {
        Step.allCases.filter { s in
            switch s {
            case .search: isPicked(.search)
            case .face: wantsFace
            default: true
            }
        }
    }

    private func go(_ delta: Int) {
        let list = steps
        guard let i = list.firstIndex(of: step), list.indices.contains(i + delta) else { return }
        step = list[i + delta]; message = nil
    }

    private func refresh() {
        face.unlock.refreshPermission()
        accessibility = AXIsProcessTrusted()
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        wifi.refresh()
        focus.retry()
        messagesAccess.refresh()
        spotlightConflict = SearchShortcut.spotlightConflict
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
