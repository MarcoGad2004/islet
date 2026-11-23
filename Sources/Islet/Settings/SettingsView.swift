import AVFoundation
import ServiceManagement
import SwiftUI

/// Settings (DESIGN.md "Settings"): pages in a sidebar, Islet's status at the top of it. What works stays quiet;
/// what doesn't is listed on the Islet page, shown on the pages it affects and badged in the sidebar.
struct SettingsView: View {
    let face: FaceUnlockCoordinator
    let levels: LevelsController
    let media: MediaMonitor
    let focus: FocusMonitor
    let wifi: WiFiController
    var runSetup: () -> Void = {}
    /// The window shows the page's name, as System Settings does.
    var setTitle: (String) -> Void = { _ in }

    @AppStorage(SettingsPage.storageKey) private var pageRaw = SettingsPage.status.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage(MenuBarIconStyle.key) private var menuBarIconStyle = MenuBarIconStyle.pill.rawValue
    @AppStorage(BatteryIconClick.key) private var batteryIconClick = BatteryIconClick.stats.rawValue
    @AppStorage(MenuBarBattery.percentKey) private var batteryIconPercent = true
    @AppStorage(GlassLook.key) private var glassLook = true
    @AppStorage(IslandStore.quickInfoKey) private var quickInfo = true
    @AppStorage(NotchGeometry.hasNotchKey) private var hasNotch = NotchGeometry.detectedNotch
    @AppStorage(NotchlessStyle.key) private var notchlessStyle = NotchlessStyle.bezel.rawValue
    @AppStorage(NotificationWatcher.enabledKey) private var notificationsInNotch = true
    @AppStorage(NotificationWatcher.hideTextKey) private var notificationsHideText = false
    @AppStorage(MessagesStore.enabledKey) private var messagesInNotch = true
    @AppStorage(SearchShortcutChoice.key) private var searchShortcut = SearchShortcutChoice.optionSpace.rawValue
    @AppStorage(WebSearchEngine.key) private var webEngine = WebSearchEngine.google.rawValue
    @AppStorage(Updater.autoCheckKey) private var autoCheckUpdates = true
    @AppStorage(Feature.levelsKey) private var levelsInNotch = true
    @AppStorage(Feature.focusKey) private var focusInNotch = true
    @AppStorage(Feature.shazamKey) private var shazamInNotch = true
    @AppStorage(SiriQuestion.enabledKey) private var askSiri = true
    @State private var spotlightConflict = SearchShortcut.spotlightConflict
    @State private var messagesAccess = MessagesAccess()
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    private let updater = Updater.shared
    private let powerMode = PowerModeController.shared

    private var page: Binding<SettingsPage?> {
        Binding(get: { SettingsPage(rawValue: pageRaw) ?? .status }, set: { if let p = $0 { pageRaw = p.rawValue } })
    }
    private var current: SettingsPage { SettingsPage(rawValue: pageRaw) ?? .status }

    private var checks: SettingsChecks {
        SettingsChecks(face: face, levels: levels, media: media, focus: focus, wifi: wifi, messagesAccess: messagesAccess,
                       camera: camera, spotlightConflict: spotlightConflict, requestCamera: requestCamera)
    }

    var body: some View {
        let issues = checks.issues
        NavigationSplitView {
            sidebar(issues)
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 260)
        } detail: {
            detail(issues)
                .navigationTitle(current.title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 680, minHeight: 460)
        .onAppear { refresh(); setTitle(current.title) }
        .onChange(of: pageRaw) { setTitle(current.title) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    /// Everything Settings shows comes from here, so it's checked again whenever the window comes back to the front.
    private func refresh() {
        face.unlock.refreshPermission(); levels.retryTap(); wifi.refresh(); focus.retry(); messagesAccess.refresh()
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        spotlightConflict = SearchShortcut.spotlightConflict
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Sidebar

    private func sidebar(_ issues: [SettingsIssue]) -> some View {
        List(selection: page) {
            statusRow(issues).tag(SettingsPage.status)
            Section {
                ForEach([SettingsPage.general, .notch, .notifications, .search, .battery, .faceUnlock]) { sidebarRow($0, issues) }
            }
            Section {
                ForEach([SettingsPage.permissions, .updates]) { sidebarRow($0, issues) }
            }
        }
        .listStyle(.sidebar)
    }

    private func statusRow(_ issues: [SettingsIssue]) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dynamic Peninsula").fontWeight(.semibold).lineLimit(1)
                // The version on its own line: the name no longer leaves room beside it.
                Text(versionLabel.components(separatedBy: " (").first!).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(issues.isEmpty ? Color.green : .orange).frame(width: 7, height: 7)
                    Text(Self.summary(issues.count)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sidebarRow(_ p: SettingsPage, _ issues: [SettingsIssue]) -> some View {
        let n = issues.filter { $0.pages.contains(p) }.count
        return Label { Text(p.title) } icon: { SettingsIcon(page: p) }
            .badge(n)
            .tag(p)
    }

    private static func summary(_ n: Int) -> String {
        switch n {
        case 0: "Everything is set up"
        case 1: "1 thing needs attention"
        default: "\(n) things need attention"
        }
    }

    // MARK: Pages

    @ViewBuilder private func detail(_ issues: [SettingsIssue]) -> some View {
        let here = issues.filter { $0.pages.contains(current) }
        switch current {
        case .status: statusPage(issues)
        case .general: general
        case .notch: notch
        case .notifications: notifications(here)
        case .search: search(here)
        case .battery: battery
        case .faceUnlock: FaceUnlockSettings(face: face, issues: here)
        case .permissions: permissions(issues)
        case .updates: updates
        }
    }

    private func statusPage(_ issues: [SettingsIssue]) -> some View {
        Form {
            Section {
                if issues.isEmpty {
                    SettingsHero(symbol: "checkmark", color: .green, title: "Everything is set up", detail: allSetDetail)
                } else {
                    SettingsHero(symbol: "exclamationmark", color: .orange, title: Self.summary(issues.count),
                                 detail: "Everything else is working. Each one below says what it affects and how to fix it.")
                }
            }
            SettingsIssuesSection(issues: issues, title: "To fix") { pageRaw = $0.rawValue }
            Section {
                ForEach(Feature.allCases) { f in
                    if f.parent == nil || f.parent!.isOn { featureRow(f) }
                }
            } header: {
                Text("Features")
            } footer: {
                SettingsCaption("Turn off what you don't use, and Dynamic Peninsula stops asking for what only it needs. The island itself, with now playing, charging and the controls, is always on.")
            }
        }
        .formStyle(.grouped)
    }

    private var allSetDetail: String {
        let p = checks.permissions
        var parts = [p.allSatisfy(\.allowed) ? "All \(p.count) permissions are allowed" : "Everything Dynamic Peninsula uses is allowed"]
        if face.faces.isReady, face.unlock.enabled { parts.append("Face Unlock is on") }
        if updater.state == .upToDate { parts.append("Dynamic Peninsula is up to date") }
        return parts.count == 1 ? parts[0] + "." : parts.dropLast().joined(separator: ", ") + " and " + parts.last! + "."
    }

    /// A feature on the Islet page: what it does, how it is, and its switch.
    @ViewBuilder private func featureRow(_ f: Feature) -> some View {
        let st = checks.state(f)
        LabeledContent {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    if let ok = st.ok { Circle().fill(ok ? Color.green : .orange).frame(width: 7, height: 7) }
                    Text(st.text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                if f == .faceUnlock, !face.faces.isReady {
                    Button("Set Up…") { pageRaw = SettingsPage.faceUnlock.rawValue }
                } else {
                    Toggle(f.title, isOn: featureBinding(f)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        } label: {
            if f.parent == nil {
                SettingsLabel(f.title, f.detail)
            } else {
                // Part of the row above: an arrow turning down and in ties it to its parent.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.callout.weight(.medium)).foregroundStyle(.tertiary)
                        .accessibilityLabel("Part of \(f.parent!.title)")
                    SettingsLabel(f.title, f.detail)
                }
            }
        }
    }

    private func featureBinding(_ f: Feature) -> Binding<Bool> {
        switch f {
        case .levels: $levelsInNotch
        case .notifications: $notificationsInNotch
        case .messages: $messagesInNotch
        case .focus: $focusInNotch
        case .shazam: $shazamInNotch
        case .faceUnlock: Binding(get: { face.unlock.enabled }, set: { face.unlock.enabled = $0 })
        case .menuBarBattery: Binding(get: { menuBarIconStyle == MenuBarIconStyle.battery.rawValue },
                                      set: { menuBarIconStyle = ($0 ? MenuBarIconStyle.battery : .pill).rawValue })
        case .search: Binding(get: { searchShortcut != SearchShortcutChoice.off.rawValue }, set: { on in
            Feature.search.set(on)
            searchShortcut = SearchShortcutChoice.current.rawValue
            refresh()
        })
        }
    }

    private var versionLabel: String {
        Bundle.main.object(forInfoDictionaryKey: "IsletBuildLabel") as? String ?? updater.currentVersion
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Open Dynamic Peninsula at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginError { Text(loginError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                Toggle(isOn: $showMenuBarIcon) {
                    SettingsLabel("Show menu bar icon", "Settings is also behind the gear in the open panel. Without a notch the icon always shows. With Battery in the menu bar on, the battery is Dynamic Peninsula's icon and always shows.")
                }
            }
            Section {
                LabeledContent {
                    Button("Run Setup…") { runSetup() }
                } label: {
                    SettingsLabel("Run setup again", "Walks through the permissions and Face Unlock again.")
                }
                LabeledContent("Quit Dynamic Peninsula") { Button("Quit") { NSApp.terminate(nil) } }
            }
        }
        .formStyle(.grouped)
    }

    private var notch: some View {
        Form {
            Section {
                Picker(selection: $hasNotch) {
                    Text("Has a notch").tag(true)
                    Text("No notch").tag(false)
                } label: {
                    SettingsLabel("This Mac", hasNotch ? "With the lid closed on an external display, Dynamic Peninsula uses the no-notch style." : "There's no notch to live in, so Dynamic Peninsula uses the style below.")
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Toggle(isOn: $glassLook) {
                    SettingsLabel("Glass look", "Below the notch the island fades from black into glass. Off, it stays solid black.")
                }
                Toggle(isOn: $quickInfo) {
                    SettingsLabel("Quick info on hover", "Move the pointer over the notch while nothing is showing to see the time, the battery, and your Wi-Fi network and Bluetooth device.")
                }
            }
            Section {
                Picker("Style", selection: $notchlessStyle) {
                    Text("Bubble from the top edge").tag(NotchlessStyle.bezel.rawValue)
                    Text("Drop down from the menu bar icon").tag(NotchlessStyle.menuBar.rawValue)
                    Text("Off").tag(NotchlessStyle.off.rawValue)
                }
            } header: {
                Text("Without a notch")
            } footer: {
                SettingsCaption(NotchChoice.caption(notchlessStyle))
            }
        }
        .formStyle(.grouped)
    }

    private func notifications(_ here: [SettingsIssue]) -> some View {
        let needs = checks.state(.messages).ok == false
        return Form {
            SettingsIssuesSection(issues: here)
            Section {
                Toggle(isOn: $notificationsInNotch) {
                    SettingsLabel("Show notifications in the notch", "Banners appear under the notch instead of the top-right corner. Calls keep their own banner. Needs Accessibility.")
                }
                if notificationsInNotch {
                    Toggle("Hide message text", isOn: $notificationsHideText)
                }
            }
            if notificationsInNotch {
                Section {
                    Toggle(isOn: $messagesInNotch) {
                        SettingsLabel("Open conversations in the notch", "Click a message banner to read and reply from the notch.")
                    }
                    if messagesInNotch, !needs {
                        Label("Has what it needs: Full Disk Access, Contacts and Control Messages", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary).symbolRenderingMode(.multicolor).font(.callout)
                    }
                } header: { Text("Messages") }
            }
        }
        .formStyle(.grouped)
    }

    private func search(_ here: [SettingsIssue]) -> some View {
        let on = searchShortcut != SearchShortcutChoice.off.rawValue
        return Form {
            Section {
                Toggle(isOn: featureBinding(.search)) {
                    SettingsLabel("Search from the notch", Feature.search.detail + " Typing in the open panel searches too.")
                }
            }
            if on {
                Section {
                    SearchShortcutChooser(shortcut: $searchShortcut)
                } header: {
                    Text("Shortcut")
                }
                Section {
                    Toggle(isOn: $askSiri) {
                        SettingsLabel("Ask Siri", "Type “siri” and your question, or just a question. Return opens Spotlight with it asked, and Siri answers there. When Dynamic Peninsula finds nothing, Ask Siri comes first too.")
                    }
                    if askSiri, !face.unlock.accessibilityTrusted {
                        Label("Needs Accessibility, to type your question into Spotlight.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout)
                    }
                    Picker("Search the web with", selection: $webEngine) {
                        ForEach(WebSearchEngine.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } header: {
                    Text("Results")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: searchShortcut) { refresh() }
        // The chooser notices Spotlight moving; the sidebar's count follows.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            spotlightConflict = SearchShortcut.spotlightConflict
        }
    }

    private var battery: some View {
        Form {
            Section {
                Toggle(isOn: featureBinding(.menuBarBattery)) {
                    SettingsLabel("Show the battery in the menu bar", "Dynamic Peninsula's menu bar icon becomes a battery, so it can stand in for the macOS one. Right-click it for Dynamic Peninsula's menu.")
                }
                if menuBarIconStyle == MenuBarIconStyle.battery.rawValue {
                    Picker(selection: $batteryIconClick) {
                        Text("Battery stats").tag(BatteryIconClick.stats.rawValue)
                        Text("Control center").tag(BatteryIconClick.controls.rawValue)
                    } label: {
                        SettingsLabel("Clicking it opens", "Battery stats: health, temperature, the last 12 hours and where the power is flowing. Control center: the panel you get from the notch.")
                    }
                    Toggle("Show percentage", isOn: $batteryIconPercent)
                    LabeledContent {
                        Button("Control Center Settings…") { SystemSettings.open(SystemSettings.controlCenter) }
                    } label: {
                        SettingsLabel("Hide the macOS battery", "In Control Center settings, set Battery to Don't Show in Menu Bar.")
                    }
                }
            } header: { Text("Menu Bar") }
            Section {
                if powerMode.permissionInstalled {
                    LabeledContent {
                        Button("Remove…") { powerMode.removePermission() }
                    } label: {
                        SettingsLabel("Switch without a password", "The battery page can switch Low Power, Automatic and High Power without asking.")
                    }
                } else {
                    SettingsLabel("Asks for your password", "The first time you switch Energy Mode on the battery page, Dynamic Peninsula asks for your password once and can then switch it without asking.")
                }
            } header: { Text("Energy Mode") }
        }
        .formStyle(.grouped)
    }

    private func permissions(_ issues: [SettingsIssue]) -> some View {
        let all = checks.permissions
        let mine = issues.filter { $0.pages.first == .permissions }
        let used = all.filter(\.needed)
        let rest = all.filter { !$0.needed }
        return Form {
            if mine.isEmpty {
                Section {
                    SettingsHero(symbol: "checkmark", color: .green, title: "Your features have what they need",
                                 detail: "Dynamic Peninsula only asks for what the features you have on use. It checks again whenever this window comes to the front.")
                }
            }
            SettingsIssuesSection(issues: mine)
            if !used.isEmpty {
                Section("Used by your features") {
                    ForEach(used) { p in
                        LabeledContent {
                            if p.allowed { Text("Allowed").foregroundStyle(.secondary) } else { Button("Allow…", action: p.allow) }
                        } label: {
                            SettingsLabel(p.name, SettingsChecks.list(p.usedBy.map(\.title)))
                        }
                    }
                }
            }
            if !rest.isEmpty {
                Section {
                    ForEach(rest) { p in
                        LabeledContent {
                            if p.allowed { Text("Allowed").foregroundStyle(.secondary) }
                            else if p.optional != nil { Button("Allow…", action: p.allow) }
                            else { Text("Off").foregroundStyle(.secondary) }
                        } label: {
                            SettingsLabel(p.name, p.optional.map { "Optional. " + $0 } ?? "Nothing you have on uses it.")
                        }
                    }
                } header: {
                    Text("Not needed")
                } footer: {
                    SettingsCaption("Never shown as a problem. Allowed ones can be switched off in System Settings > Privacy & Security.")
                }
            }
            Section {
                LabeledContent {
                    Text(media.available ? "Working" : "Unavailable").foregroundStyle(.secondary)
                } label: {
                    SettingsLabel("Now playing", "Reads what's playing through a helper built into Dynamic Peninsula.")
                }
            } header: { Text("Not a permission") }
        }
        .formStyle(.grouped)
    }

    private var updates: some View {
        Form {
            Section {
                LabeledContent {
                    switch updater.state {
                    case .idle, .upToDate, .failed: Button("Check Now") { updater.check() }
                    case .checking, .downloading: ProgressView().controlSize(.small)
                    case .available(let tag):
                        HStack {
                            if !updater.notes.isEmpty { Button("Release Notes…") { updater.showNotes(tag) } }
                            Button("Install and Restart") { updater.install(tag) }.buttonStyle(.borderedProminent)
                        }
                    }
                } label: {
                    SettingsLabel(updateTitle, "You have \(versionLabel).")
                }
                .help("Based on \(updater.currentVersion). Check Now still offers the release itself.")
                if case .failed(let m) = updater.state {
                    Text(m).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: $autoCheckUpdates) {
                    SettingsLabel("Check for updates automatically", "Looks at GitHub about every 6 hours. A new version shows an Update pill next to the battery in the panel.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var updateTitle: String {
        switch updater.state {
        case .available(let tag): "Dynamic Peninsula \(Updater.plain(tag)) is available"
        case .upToDate: "Dynamic Peninsula is up to date"
        case .checking: "Checking…"
        case .downloading: "Updating; follow along in the notch"
        case .failed: "Couldn't check for updates"
        case .idle: "Dynamic Peninsula \(updater.currentVersion)"
        }
    }

    // MARK: Actions

    private func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil } catch {
            loginError = "Couldn't change launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func requestCamera() {
        if camera == .notDetermined {
            Task { _ = await FaceCamera.requestAccess(); camera = AVCaptureDevice.authorizationStatus(for: .video) }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
