import SwiftUI

/// Settings > Face Unlock: one status line, then the face and password, testing, protection and removing it.
struct FaceUnlockSettings: View {
    let face: FaceUnlockCoordinator
    let issues: [SettingsIssue]

    private enum Step { case overview, password, scanning }
    @State private var step = Step.overview
    @State private var password = ""
    @State private var message: String?
    @State private var busy = false
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section { hero }
            SettingsIssuesSection(issues: issues)
            switch step {
            case .overview: setup
            case .password: passwordStep
            case .scanning: scanningStep
            }
            if face.faces.isEnrolled {
                testSection
                protectionSection
            }
            if face.faces.isEnrolled || face.faces.hasPassword {
                Section {
                    LabeledContent {
                        Button("Remove…", role: .destructive) { confirmRemove = true }
                    } label: {
                        SettingsLabel("Remove face and password", "Deletes the face data and login password from the Keychain.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: face.enrolment?.phase) { _, phase in
            if step == .scanning, phase != nil, phase != .scanning { step = .overview }
        }
        .onAppear { face.unlock.refreshPermission() }
        .confirmationDialog("Remove face unlock?", isPresented: $confirmRemove) {
            Button("Remove face and password", role: .destructive) { face.stopTest(); face.faces.removeAll() }
        } message: { Text("Deletes the stored face data and login password from the Keychain.") }
    }

    private var hero: some View {
        let unlock = face.unlock
        let ready = face.faces.isReady
        let on = ready && unlock.enabled && issues.isEmpty
        return SettingsHero(
            symbol: "faceid",
            color: on ? .teal : (issues.isEmpty ? .gray : .orange),
            title: !ready ? "Face Unlock isn't set up" : !unlock.enabled ? "Face Unlock is off" : issues.isEmpty ? "Face Unlock is on" : "Face Unlock needs attention",
            detail: "Unlocks this Mac's lock screen with the camera. Your face and login password stay in this Mac's Keychain, and the password is only ever typed into the lock screen. It's convenient, but not as strong as Touch ID.")
    }

    // MARK: Face and password

    @ViewBuilder private var setup: some View {
        Section {
            if face.faces.isReady {
                Toggle("Unlock this Mac with my face", isOn: Binding(get: { face.unlock.enabled }, set: { face.unlock.enabled = $0 }))
            }
            LabeledContent {
                Button(face.faces.isEnrolled ? "Scan Again…" : "Set Up…") { Task { await begin() } }
                    .disabled(busy || !face.modelAvailable)
            } label: {
                SettingsLabel("Face", face.faces.isEnrolled ? learnedText(enrolled: true) : "Not set up")
            }
            if face.faces.hasPassword {
                LabeledContent {
                    Button("Change…") { Task { await begin(passwordOnly: true) } }.disabled(busy)
                } label: {
                    SettingsLabel("Login password", "Stored in the Keychain")
                }
            }
            if let message {
                Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var passwordStep: some View {
        Section {
            SettingsCaption("Enter your Mac login password. It's checked against your account, then stored only in this Mac's Keychain.")
            SecureField("Login password", text: $password)
                .onSubmit { Task { await savePassword() } }
            if let message {
                Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { password = ""; message = nil; step = .overview }
                Button("Save") { Task { await savePassword() } }
                    .buttonStyle(.borderedProminent).disabled(password.isEmpty || busy)
            }
        } header: { Text("Login password") }
    }

    private var scanningStep: some View {
        Section {
            HStack {
                Text("Look at the notch at the top of your screen and slowly move your head in a circle. Keep the dot touching the ring all the way round.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Cancel") { face.cancelEnrolment(); step = .overview }
            }
        } header: { Text("Scanning") }
    }

    private func learnedText(enrolled: Bool) -> String {
        let n = face.faces.learned.count
        return n == 0 ? "Enrolled" : "Enrolled · \(n) of \(FaceStore.maxLearned) looks learned"
    }

    // MARK: Testing

    private var testSection: some View {
        Section {
            LabeledContent {
                Button(face.testingFace ? "Stop" : "Start Test") {
                    Task { if face.testingFace { face.stopTest() } else { message = await face.startTest() } }
                }.disabled(face.isEnrolling)
            } label: {
                SettingsLabel("Try your face, then someone else's",
                              "Set the threshold between the two scores. Blink, smile and turn your head each way: each should tick. A photo of you should say Photo edge or Fake and tick nothing. Check light shows whether the screen-light check would vouch for what's in front of the camera; in direct sun it should say Harsh light.")
            }
            if face.testingFace { testResult }
            LabeledContent {
                Text(String(format: "%.2f", face.faces.effectiveThreshold)).monospacedDigit()
            } label: {
                SettingsLabel("Match threshold", thresholdText)
            }
        } header: { Text("Test recognition") }
    }

    /// How the threshold in use was set: the security level, then your own scores.
    private var thresholdText: String {
        let faces = face.faces, level = faces.security.title
        guard faces.learnFromUnlocks else { return "Set by \(level). Turn on learning to fit it to your face." }
        let n = faces.genuineScores.count
        if n < AdaptiveThreshold.minimum { return "Set by \(level) · learning your scores: \(n) of \(AdaptiveThreshold.minimum) unlocks" }
        return "Set by \(level), just under your usual scores from your last \(n) unlocks"
    }

    private var testResult: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let score = face.testScore {
                // In harsh light a fake-looking score asks for the challenge instead of refusing. Standard and More
                // secure doubt a fake-looking face rather than refuse it: it needs the glow and the challenge.
                let level = face.faces.security
                let fake = (face.testLive.map { $0 < level.refuseLevel } ?? false) && !(face.testLighting?.harsh ?? false)
                let refused = face.testFramed || (fake && !level.usesGlow)
                let match = score >= face.faces.effectiveThreshold && !refused && !fake
                Label(String(format: "%.2f  %@", score, face.testFramed ? "Photo edge" : refused ? "Fake"
                             : score < face.faces.effectiveThreshold ? "No match" : fake ? "Doubtful: needs glow and \(Self.challengeWord(level))" : "Match"),
                      systemImage: match ? "checkmark.circle.fill" : refused || score < face.faces.effectiveThreshold ? "xmark.circle.fill" : "questionmark.circle.fill")
                    .foregroundStyle(match ? .green : refused || score < face.faces.effectiveThreshold ? .red : .orange).monospacedDigit()
            } else {
                Text("No face in view").foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                if let live = face.testLive {
                    let level = face.faces.security
                    let label = live >= level.liveLevel ? "Real" : live < level.refuseLevel ? (level.usesGlow ? "Fake: would doubt" : "Fake") : level.usesGlow ? "Unsure: would glow" : "Unsure: would ask"
                    Label(String(format: "Spoof model: %@ %.2f", label, live), systemImage: "person.crop.square.badge.camera")
                        .foregroundStyle(live >= level.liveLevel ? .green : live < level.refuseLevel ? .red : .secondary)
                        .monospacedDigit()
                } else if face.antiSpoof == nil {
                    Text("Spoof model missing").foregroundStyle(.secondary)
                }
                Button(face.testPulsing ? "Checking…" : "Check Light") { Task { await face.runTestPulse() } }
                    .disabled(face.testPulsing)
                if let verdict = face.testPulse { pulseText(verdict) }
            }
            .font(.callout)
            HStack(spacing: 14) {
                ForEach(LivenessChallenge.allCases, id: \.self) { c in
                    let seen = face.testSeen.contains(c)
                    Label(Self.testLabel(c), systemImage: seen ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(seen ? .green : .secondary)
                }
                if let l = face.testLighting {
                    Label(String(format: "%@ · sides %.1f× · %.0f%% blown out", l.harsh ? "Harsh light: asks at once" : "Even light", l.sideRatio, l.clipped * 100),
                          systemImage: l.harsh ? "sun.max.fill" : "sun.min")
                        .foregroundStyle(l.harsh ? .orange : .secondary).monospacedDigit()
                }
                if let light = face.testLight {
                    Label(String(format: "Light %.2f%@", light, light < 0.25 ? " (dark)" : ""), systemImage: "sun.min")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.callout)
        }
    }

    private static func challengeWord(_ level: FaceSecurity) -> String { level.randomChallenge ? "a challenge" : "a blink" }

    private func pulseText(_ v: FacePulse.Verdict) -> some View {
        let r = v.reading
        var parts = [v.passed ? "Vouches" : "Can't vouch: \(v.reason ?? "")"]
        if let r {
            if let c = r.contrast, let s = r.shape {
                parts.append(String(format: "depth %.2f, shape %.2f", c, s))
            } else {
                parts.append(String(format: "no background · face shape %.2f", r.relative))
            }
            if let a = r.agreement { parts.append(String(format: "yours %.2f", a)) }
        }
        if let lux = face.testLux { parts.append(String(format: "%.0f lux", lux)) }
        return Label(parts.joined(separator: " · "), systemImage: v.passed ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(v.passed ? .green : .secondary).monospacedDigit()
    }

    private static func testLabel(_ c: LivenessChallenge) -> String {
        switch c {
        case .blink: "Blink"
        case .smile: "Smile"
        case .turnLeft: "Left"
        case .turnRight: "Right"
        }
    }

    // MARK: Protection

    private var protectionSection: some View {
        let faces = face.faces
        return Section {
            Picker(selection: Binding(get: { faces.security }, set: { faces.security = $0 })) {
                ForEach(FaceSecurity.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                SettingsLabel("Security", faces.security.summary)
            }
            if face.antiSpoof == nil {
                Text("The spoof model is missing from this build, so every unlock needs the glow or a challenge.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Toggle(isOn: Binding(get: { faces.learnFromUnlocks }, set: { faces.learnFromUnlocks = $0 })) {
                SettingsLabel("Learn my face from unlocks",
                              "Adapts to new light, glasses or a haircut, and after \(AdaptiveThreshold.minimum) unlocks fits the match threshold to your usual scores, as tightly as the security level asks. Keeps only unlocks that matched your first scan well, so it doesn't drift.")
            }
            LabeledContent {
                if !faces.learned.isEmpty || !faces.pulseProfiles.isEmpty || !faces.genuineScores.isEmpty { Button("Forget") { faces.forgetLearned() } }
            } label: {
                SettingsLabel("Learned looks", learnedSummary)
            }
        } header: {
            Text("Security and learning")
        } footer: {
            SettingsCaption("A photo or phone held up to the camera is always refused. Each level tries the quietest check first: a model that tells a real face from a print or a screen, then (Standard and More secure) a brief glow of the screen, which a real face answers by its shape, then a challenge as the last resort. In a dark room the screen brightens to light your face.")
        }
    }

    private var learnedSummary: String {
        let f = face.faces
        let looks = f.learned.isEmpty ? "None yet" : "\(f.learned.count) of \(FaceStore.maxLearned)"
        return f.pulseProfiles.isEmpty ? looks : "\(looks) · light pattern from \(f.pulseProfiles.count) unlocks"
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
