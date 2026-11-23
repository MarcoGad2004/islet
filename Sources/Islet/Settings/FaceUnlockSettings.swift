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
                HStack {
                    Slider(value: Binding(get: { Double(face.faces.threshold) }, set: { face.faces.threshold = Float($0) }), in: 0.25...0.75)
                        .frame(maxWidth: 220)
                    Text(String(format: "%.2f", face.faces.threshold)).monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            } label: {
                SettingsLabel("Match threshold", thresholdText)
            }
        } header: { Text("Test recognition") }
    }

    private var thresholdText: String {
        let faces = face.faces
        guard faces.adaptiveThreshold else { return "" }
        let n = faces.genuineScores.count
        if n < AdaptiveThreshold.minimum { return "Learning your scores: \(n) of \(AdaptiveThreshold.minimum) unlocks" }
        return String(format: "In use: %.2f, from your last %d unlocks. The slider is the floor.", faces.effectiveThreshold, n)
    }

    private var testResult: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let score = face.testScore {
                // In harsh light a fake-looking score asks for the challenge instead of refusing.
                let fake = (face.testLive.map { $0 < SpoofTracker.spoofLevel } ?? false) && !(face.testLighting?.harsh ?? false)
                let match = score >= face.faces.effectiveThreshold && !face.testFramed && !fake
                Label(String(format: "%.2f  %@", score, face.testFramed ? "Photo edge" : fake ? "Fake" : match ? "Match" : "No match"),
                      systemImage: match ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(match ? .green : .red).monospacedDigit()
            } else {
                Text("No face in view").foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                if let live = face.testLive {
                    let label = live >= SpoofTracker.liveLevel ? "Real" : live < SpoofTracker.spoofLevel ? "Fake" : "Unsure"
                    Label(String(format: "Spoof model: %@ %.2f", label, live), systemImage: "person.crop.square.badge.camera")
                        .foregroundStyle(live >= SpoofTracker.liveLevel ? .green : live < SpoofTracker.spoofLevel ? .red : .secondary)
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
            Picker("Prove it's live", selection: Binding(get: { faces.liveness }, set: { faces.liveness = $0 })) {
                Text("Automatic: screen light, then a challenge if needed").tag(LivenessMode.automatic)
                Text("Random: blink, smile or turn your head").tag(LivenessMode.random)
                Text("Blink").tag(LivenessMode.blink)
                Text("Off").tag(LivenessMode.off)
            }
            if faces.liveness == .automatic {
                Toggle(isOn: Binding(get: { faces.blinkFallback }, set: { faces.blinkFallback = $0 })) {
                    SettingsLabel("When a challenge is needed, just ask me to blink",
                                  "Instead of a random blink, smile or head turn. Simpler, but a video of you blinking could pass it more easily.")
                }
            }
            Toggle("Brighten the screen to light my face in the dark", isOn: Binding(get: { faces.brightenInDark }, set: { faces.brightenInDark = $0 }))
            Toggle(isOn: Binding(get: { faces.spoofModel }, set: { faces.spoofModel = $0 })) {
                SettingsLabel("Refuse faces that look like a photo or screen",
                              face.antiSpoof == nil ? "The spoof model is missing from this build." : "A small model trained to tell a real face from a print or a screen. Runs on this Mac.")
            }.disabled(face.antiSpoof == nil)
            Toggle(isOn: Binding(get: { faces.adaptiveThreshold }, set: { faces.adaptiveThreshold = $0 })) {
                SettingsLabel("Raise the threshold as it learns my face",
                              "After \(AdaptiveThreshold.minimum) unlocks, sets the threshold just under your usual scores, up to \(String(format: "%.2f", AdaptiveThreshold.maxRaise)) above the slider. Only your own unlocks move it.")
            }
            Toggle(isOn: Binding(get: { faces.learnFromUnlocks }, set: { faces.learnFromUnlocks = $0 })) {
                SettingsLabel("Learn from successful unlocks",
                              "Adapts to new light, glasses or a haircut. Keeps only unlocks that passed the live check and matched your first scan well, so it doesn't drift.")
            }
            LabeledContent {
                if !faces.learned.isEmpty || !faces.pulseProfiles.isEmpty || !faces.genuineScores.isEmpty { Button("Forget") { faces.forgetLearned() } }
            } label: {
                SettingsLabel("Learned looks", learnedSummary)
            }
        } header: {
            Text("Protection and learning")
        } footer: {
            SettingsCaption("A photo or phone held up to the camera is always refused. Automatic swells the screen brightness once after your face matches: a real face lights up by its shape, a photo or screen doesn't. When that and the spoof model both agree, it unlocks with nothing to do; otherwise (a bright room, say) it asks for a blink, a smile or a head turn, like Random.")
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
