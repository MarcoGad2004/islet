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
    @AppStorage(GlassLook.key) private var glassLook = true
    @AppStorage(NotchGeometry.hasNotchKey) private var hasNotch = NotchGeometry.detectedNotch
    @AppStorage(NotchlessStyle.key) private var notchlessStyle = NotchlessStyle.bezel.rawValue
    @AppStorage(NotificationWatcher.enabledKey) private var notificationsInNotch = true
    @AppStorage(NotificationWatcher.hideTextKey) private var notificationsHideText = false
    @AppStorage(MessagesStore.enabledKey) private var messagesInNotch = true
    @AppStorage(LiveActivityWatcher.enabledKey) private var liveActivitiesInNotch = true
    @AppStorage(SearchShortcutChoice.key) private var searchShortcut = SearchShortcutChoice.commandSpace.rawValue
    @AppStorage(WebSearchEngine.key) private var webEngine = WebSearchEngine.google.rawValue
    @AppStorage(Updater.autoCheckKey) private var autoCheckUpdates = true
    @State private var spotlightConflict = SearchShortcut.spotlightConflict
    @State private var messagesAccess = MessagesAccess()
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showAllPermissions = false
    private let updater = Updater.shared
    private let powerMode = PowerModeController.shared

    private var page: Binding<SettingsPage?> {
        Binding(get: { SettingsPage(rawValue: pageRaw) ?? .status }, set: { if let p = $0 { pageRaw = p.rawValue } })
    }
    private var current: SettingsPage { SettingsPage(rawValue: pageRaw) ?? .status }

    private var checks: SettingsChecks {
        SettingsChecks(face: face, levels: levels, media: media, focus: focus, wifi: wifi, messagesAccess: messagesAccess,
                       camera: camera, spotlightConflict: spotlightConflict, notificationsOn: notificationsInNotch,
                       messagesOn: messagesInNotch, requestCamera: requestCamera)
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
                Text("Islet " + versionLabel.components(separatedBy: " (").first!).fontWeight(.semibold)
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
            Section("At a glance") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    tile(.notifications, notificationsSummary, issues)
                    tile(.search, searchSummary, issues)
                    tile(.faceUnlock, faceSummary, issues)
                    tile(.notch, (hasNotch ? "Has a notch" : "No notch") + (glassLook ? " · Glass" : " · Black"), issues)
                    tile(.battery, powerMode.permissionInstalled ? "Energy Mode without a password" : "Energy Mode asks for a password", issues)
                    tile(.updates, updatesSummary, issues)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var allSetDetail: String {
        let p = checks.permissions
        var parts = [p.allSatisfy(\.allowed) ? "All \(p.count) permissions are allowed" : "Everything Islet uses is allowed"]
        if face.faces.isReady, face.unlock.enabled { parts.append("Face Unlock is on") }
        if updater.state == .upToDate { parts.append("Islet is up to date") }
        return parts.count == 1 ? parts[0] + "." : parts.dropLast().joined(separator: ", ") + " and " + parts.last! + "."
    }

    private func tile(_ p: SettingsPage, _ text: String, _ issues: [SettingsIssue]) -> some View {
        let warn = issues.contains { $0.pages.contains(p) }
        return Button { pageRaw = p.rawValue } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) { SettingsIcon(page: p, size: 18); Text(p.title).fontWeight(.semibold) }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Circle().fill(warn ? Color.orange : .green).frame(width: 6, height: 6)
                    Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var notificationsSummary: String {
        guard notificationsInNotch else { return "Off" }
        if messagesInNotch, !focus.accessGranted || SettingsChecks.debugIssues { return "Messages need Full Disk Access" }
        return messagesInNotch ? "In the notch, with Messages" : "In the notch"
    }
    private var searchSummary: String {
        guard let c = SearchShortcutChoice(rawValue: searchShortcut), c != .off else { return "No shortcut" }
        return "\(c.title) · \((WebSearchEngine(rawValue: webEngine) ?? .google).title)"
    }
    private var faceSummary: String {
        guard face.faces.isReady else { return "Not set up" }
        guard face.unlock.enabled else { return "Off" }
        let n = face.faces.learned.count
        return n == 0 ? "On" : "On · \(n) of \(FaceStore.maxLearned) looks learned"
    }
    private var updatesSummary: String {
        switch updater.state {
        case .available(let tag): "\(Updater.plain(tag)) ready to install"
        case .upToDate: "\(versionLabel) · Up to date"
        default: versionLabel
        }
    }
    private var versionLabel: String {
        Bundle.main.object(forInfoDictionaryKey: "IsletBuildLabel") as? String ?? updater.currentVersion
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Open Islet at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginError { Text(loginError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                Toggle(isOn: $showMenuBarIcon) {
                    SettingsLabel("Show menu bar icon", "Settings is also behind the gear in the open panel. Without a notch the icon always shows.")
                }
            }
            Section {
                LabeledContent {
                    Button("Run Setup…") { runSetup() }
                } label: {
                    SettingsLabel("Run setup again", "Walks through the permissions and Face Unlock again.")
                }
                LabeledContent("Quit Islet") { Button("Quit") { NSApp.terminate(nil) } }
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
                    SettingsLabel("This Mac", hasNotch ? "With the lid closed on an external display, Islet uses the no-notch style." : "There's no notch to live in, so Islet uses the style below.")
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Toggle(isOn: $glassLook) {
                    SettingsLabel("Glass look", "Below the notch the island fades from black into glass. Off, it stays solid black.")
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
        let needs = !focus.accessGranted || SettingsChecks.debugIssues || !messagesAccess.contactsAllowed || !messagesAccess.automationAllowed
        return Form {
            SettingsIssuesSection(issues: here)
            Section {
                Toggle(isOn: $notificationsInNotch) {
                    SettingsLabel("Show notifications in the notch", "Banners appear under the notch instead of the top-right corner. Calls keep their own banner.")
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
            if AppDelegate.liveActivitiesEnabled {
                Section {
                    Toggle(isOn: $liveActivitiesInNotch) {
                        SettingsLabel("Show iPhone Live Activities in the notch", "The app and its live value beside the notch, the details in the panel. The menu bar keeps its own as well.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func search(_ here: [SettingsIssue]) -> some View {
        Form {
            SettingsIssuesSection(issues: here)
            Section {
                Picker(selection: $searchShortcut) {
                    ForEach(SearchShortcutChoice.allCases) { Text($0.title).tag($0.rawValue) }
                } label: {
                    SettingsLabel("Shortcut", "Search apps, files, contacts, Shortcuts and settings from the notch. Typing in the open panel searches too.")
                }
                .onChange(of: searchShortcut) {
                    SearchShortcut.shared.apply()
                    spotlightConflict = SearchShortcut.spotlightConflict
                }
                if searchShortcut != SearchShortcutChoice.off.rawValue {
                    Picker("Search the web with", selection: $webEngine) {
                        ForEach(WebSearchEngine.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var battery: some View {
        Form {
            Section {
                if powerMode.permissionInstalled {
                    LabeledContent {
                        Button("Remove…") { powerMode.removePermission() }
                    } label: {
                        SettingsLabel("Switch without a password", "The battery page can switch Low Power, Automatic and High Power without asking.")
                    }
                } else {
                    SettingsLabel("Asks for your password", "The first time you switch Energy Mode on the battery page, Islet asks for your password once and can then switch it without asking.")
                }
            } header: { Text("Energy Mode") }
        }
        .formStyle(.grouped)
    }

    private func permissions(_ issues: [SettingsIssue]) -> some View {
        let all = checks.permissions
        let mine = issues.filter { $0.pages.first == .permissions }
        let quiet = all.filter { $0.allowed || !$0.needed }
        return Form {
            if mine.isEmpty {
                Section {
                    SettingsHero(symbol: "checkmark", color: .green,
                                 title: all.allSatisfy(\.allowed) ? "All \(all.count) permissions are allowed" : "Everything Islet uses is allowed",
                                 detail: "Islet checks again whenever this window comes to the front.")
                }
            }
            SettingsIssuesSection(issues: mine)
            Section {
                DisclosureGroup(isExpanded: Binding(get: { showAllPermissions || !mine.isEmpty }, set: { showAllPermissions = $0 })) {
                    ForEach(quiet) { p in
                        LabeledContent {
                            if p.allowed { Text("Allowed").foregroundStyle(.secondary) } else { Button("Allow…", action: p.allow) }
                        } label: {
                            SettingsLabel(p.name, p.allowed ? p.purpose : p.purpose + ". Not needed for what's turned on.")
                        }
                    }
                } label: {
                    Text(mine.isEmpty ? "What each one is for" : "\(quiet.count) more")
                }
            }
            Section {
                LabeledContent {
                    Text(media.available ? "Working" : "Unavailable").foregroundStyle(.secondary)
                } label: {
                    SettingsLabel("Now playing", "Reads what's playing through a helper built into Islet.")
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
        case .available(let tag): "Islet \(Updater.plain(tag)) is available"
        case .upToDate: "Islet is up to date"
        case .checking: "Checking…"
        case .downloading: "Updating; follow along in the notch"
        case .failed: "Couldn't check for updates"
        case .idle: "Islet \(updater.currentVersion)"
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
