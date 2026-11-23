import Foundation
import Security
import OpenDirectory
import LocalAuthentication

/// Generic-password Keychain items for this app only. Values are never logged.
enum KeychainStore {
    static let service = "com.marcogad.islet.faceunlock"

    static func save(_ data: Data, account: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func delete(account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

/// Face data and the stored login password. Both stay in the Keychain on this Mac.
@MainActor @Observable
final class FaceStore {
    private static let facesAccount = "face-embeddings"
    private static let learnedAccount = "face-learned"
    private static let passwordAccount = "login-password"
    private static let thresholdKey = "faceUnlockThreshold"
    /// Before 1.6 liveness was a mode (off, automatic, blink, random); it's carried over to the nearest level.
    private static let livenessKey = "faceUnlockLiveness"
    private static let securityKey = "faceUnlockSecurity"
    private static let learnKey = "faceUnlockLearn"
    private static let scoresKey = "faceUnlockGenuineScores"
    private static let pulseKey = "faceUnlockPulseProfiles2" // v1 profiles were relative to the background
    /// Unlock scores kept for the adaptive threshold, and learned pulse patterns.
    static let maxScores = 60
    static let maxPulseProfiles = 20
    /// Learned looks kept on top of the enrolment; the oldest is dropped past this.
    static let maxLearned = 24

    /// The enrolment scan. Never changed by learning.
    private(set) var embeddings: [[Float]] = []
    /// Looks added from successful, live unlocks (new lighting, glasses, haircut). Each one had to match the
    /// enrolment itself, comfortably above the threshold, so the set can't drift towards someone else.
    private(set) var learned: [[Float]] = []
    private(set) var hasPassword = false
    /// Cosine-similarity score a probe needs to count as a match. Tune with "Test recognition". Once it has learned
    /// from enough unlocks, this is the floor the adaptive threshold never goes below.
    var threshold: Float {
        didSet { UserDefaults.standard.set(threshold, forKey: Self.thresholdKey) }
    }
    /// Typical scores of your confirmed unlocks (and of misses you then unlocked with the password), newest last.
    private(set) var genuineScores: [Float]
    /// How your face responded to the brightness pulse on confirmed unlocks (FacePulse.Reading.profile).
    private(set) var pulseProfiles: [[Double]]
    /// The threshold a scan uses: raised towards your usual scores while learning is on.
    var effectiveThreshold: Float {
        learnFromUnlocks ? AdaptiveThreshold.value(floor: threshold, scores: genuineScores) : threshold
    }

    /// How hard it checks the face is live before unlocking.
    var security: FaceSecurity { didSet { UserDefaults.standard.set(security.rawValue, forKey: Self.securityKey) } }
    /// Learn from successful unlocks: new looks, your usual scores (which raise the threshold) and how your face
    /// answers the glow.
    var learnFromUnlocks: Bool { didSet { UserDefaults.standard.set(learnFromUnlocks, forKey: Self.learnKey) } }

    var isEnrolled: Bool { !embeddings.isEmpty }
    var isReady: Bool { isEnrolled && hasPassword }
    /// What a scan compares against.
    var allEmbeddings: [[Float]] { embeddings + learned }

    init() {
        UserDefaults.standard.register(defaults: [Self.learnKey: true])
        let t = UserDefaults.standard.float(forKey: Self.thresholdKey)
        threshold = t > 0 ? t : 0.45
        let d = UserDefaults.standard
        security = d.string(forKey: Self.securityKey).flatMap(FaceSecurity.init(rawValue:))
            ?? Self.migratedSecurity(d.string(forKey: Self.livenessKey))
        learnFromUnlocks = d.bool(forKey: Self.learnKey)
        genuineScores = (d.array(forKey: Self.scoresKey) as? [NSNumber])?.map(\.floatValue) ?? []
        pulseProfiles = (d.array(forKey: Self.pulseKey) as? [[NSNumber]])?.map { $0.map(\.doubleValue) } ?? []
        reload()
    }

    /// The pre-1.6 mode's nearest level: random challenges were the strictest, off the most relaxed.
    nonisolated static func migratedSecurity(_ liveness: String?) -> FaceSecurity {
        switch liveness {
        case "random": .secure
        case "off": .faster
        default: .standard
        }
    }

    func reload() {
        embeddings = Self.loadList(Self.facesAccount)
        learned = Self.loadList(Self.learnedAccount)
        hasPassword = KeychainStore.load(account: Self.passwordAccount) != nil
    }

    private static func loadList(_ account: String) -> [[Float]] {
        KeychainStore.load(account: account).flatMap { try? JSONDecoder().decode([[Float]].self, from: $0) } ?? []
    }

    /// A new enrolment replaces the old one and forgets what was learned on top of it.
    func saveEmbeddings(_ list: [[Float]]) -> Bool {
        guard let data = try? JSONEncoder().encode(list), KeychainStore.save(data, account: Self.facesAccount) else { return false }
        embeddings = list
        forgetLearned()
        return true
    }

    /// Learns from a live, successful unlock. Returns true when the sample was kept.
    @discardableResult func learn(_ sample: [Float]) -> Bool {
        guard learnFromUnlocks, isEnrolled,
              FaceLearning.shouldLearn(sample, enrolled: embeddings, learned: learned, threshold: threshold) else { return false }
        var list = learned + [sample]
        if list.count > Self.maxLearned { list.removeFirst(list.count - Self.maxLearned) }
        guard let data = try? JSONEncoder().encode(list), KeychainStore.save(data, account: Self.learnedAccount) else { return false }
        learned = list
        return true
    }

    /// Clears learned looks, and with them the scores and pulse patterns learned on top of the enrolment.
    func forgetLearned() {
        KeychainStore.delete(account: Self.learnedAccount); learned = []
        genuineScores = []; UserDefaults.standard.removeObject(forKey: Self.scoresKey)
        pulseProfiles = []; UserDefaults.standard.removeObject(forKey: Self.pulseKey)
    }

    /// A score that was really you: the typical score of a confirmed face unlock, or the best of a miss that you
    /// unlocked with the password right after.
    func recordGenuine(_ score: Float) {
        guard score > 0 else { return }
        genuineScores = Array((genuineScores + [score]).suffix(Self.maxScores))
        UserDefaults.standard.set(genuineScores, forKey: Self.scoresKey)
    }

    /// How your face responded to a passing pulse on a confirmed unlock.
    func learnPulse(_ profile: [Double]) {
        guard learnFromUnlocks, profile.count == FacePulse.Patch.allCases.count else { return }
        pulseProfiles = Array((pulseProfiles + [profile]).suffix(Self.maxPulseProfiles))
        UserDefaults.standard.set(pulseProfiles, forKey: Self.pulseKey)
    }

    func savePassword(_ password: String) -> Bool {
        let ok = KeychainStore.save(Data(password.utf8), account: Self.passwordAccount)
        hasPassword = ok || hasPassword
        return ok
    }

    /// The stored login password, for the unlock service only.
    func password() -> String? { KeychainStore.load(account: Self.passwordAccount).flatMap { String(data: $0, encoding: .utf8) } }

    func removeFace() { KeychainStore.delete(account: Self.facesAccount); embeddings = []; forgetLearned() }
    func removePassword() { KeychainStore.delete(account: Self.passwordAccount); hasPassword = false }
    func removeAll() { removeFace(); removePassword() }
}

/// The rules for adding a learned look. Pure, so they can be tested.
enum FaceLearning {
    /// How far above the threshold a sample must score against the enrolment itself to be learned.
    static let margin: Float = 0.08
    /// A sample this similar to one already kept adds nothing new.
    static let redundant: Float = 0.92

    static func shouldLearn(_ sample: [Float], enrolled: [[Float]], learned: [[Float]], threshold: Float) -> Bool {
        guard !enrolled.isEmpty else { return false }
        // Anchored to the enrolment, not to earlier learned looks, so learning can't creep away from your face.
        guard FaceMatcher.score(sample, enrolled: enrolled) >= threshold + margin else { return false }
        let nearest = (enrolled + learned).map { FaceMatcher.cosine(sample, $0) }.max() ?? 0
        return nearest < redundant
    }
}

/// The adaptive threshold. Pure, so it can be tested.
///
/// It sits just under where your own unlocks usually score (their 5th percentile, less a margin), so about 1 unlock in
/// 20 would land in the margin rather than fail. It never goes below the threshold you set, nor more than `maxRaise`
/// above it. Only your own confirmed unlocks raise it; a failed scan can't lower it, only a miss that you then
/// unlocked with the password can (it's added as one of your scores).
enum AdaptiveThreshold {
    /// Scores needed before it moves at all.
    static let minimum = 20
    static let margin: Float = 0.05
    static let maxRaise: Float = 0.15
    static let ceiling: Float = 0.75

    static func value(floor: Float, scores: [Float]) -> Float {
        guard scores.count >= minimum else { return floor }
        let s = scores.sorted()
        let low = s[Int((Double(s.count - 1) * 0.05).rounded(.down))]
        return max(floor, min(low - margin, floor + maxRaise, ceiling))
    }
}

enum IdentityCheck {
    /// Touch ID, Apple Watch or the login password, via the system prompt.
    static func confirmOwner(reason: String) async -> Bool {
        let ctx = LAContext()
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// Checks the password against this Mac's account without logging in or changing anything.
    static func verifyLoginPassword(_ password: String) -> Bool {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            try record.verifyPassword(password)
            return true
        } catch { return false }
    }
}
