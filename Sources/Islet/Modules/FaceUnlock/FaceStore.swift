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
    /// Before 1.1.4 liveness was a blink on/off switch; turning it off is carried over.
    private static let requireBlinkKey = "faceUnlockRequireBlink"
    private static let livenessKey = "faceUnlockLiveness"
    private static let learnKey = "faceUnlockLearn"
    private static let brightenKey = "faceUnlockBrighten"
    /// Learned looks kept on top of the enrolment; the oldest is dropped past this.
    static let maxLearned = 24

    /// The enrolment scan. Never changed by learning.
    private(set) var embeddings: [[Float]] = []
    /// Looks added from successful, live unlocks (new lighting, glasses, haircut). Each one had to match the
    /// enrolment itself, comfortably above the threshold, so the set can't drift towards someone else.
    private(set) var learned: [[Float]] = []
    private(set) var hasPassword = false
    /// Cosine-similarity score a probe needs to count as a match. Tune with "Test recognition".
    var threshold: Float {
        didSet { UserDefaults.standard.set(threshold, forKey: Self.thresholdKey) }
    }

    /// What the face has to do before it unlocks, so a photo (or, with random challenges, a video) can't.
    var liveness: LivenessMode { didSet { UserDefaults.standard.set(liveness.rawValue, forKey: Self.livenessKey) } }
    /// Add new looks from successful unlocks.
    var learnFromUnlocks: Bool { didSet { UserDefaults.standard.set(learnFromUnlocks, forKey: Self.learnKey) } }
    /// Raise the screen brightness while scanning in a dark room.
    var brightenInDark: Bool { didSet { UserDefaults.standard.set(brightenInDark, forKey: Self.brightenKey) } }

    var isEnrolled: Bool { !embeddings.isEmpty }
    var isReady: Bool { isEnrolled && hasPassword }
    /// What a scan compares against.
    var allEmbeddings: [[Float]] { embeddings + learned }

    init() {
        UserDefaults.standard.register(defaults: [Self.learnKey: true, Self.brightenKey: true])
        let t = UserDefaults.standard.float(forKey: Self.thresholdKey)
        threshold = t > 0 ? t : 0.45
        let d = UserDefaults.standard
        liveness = d.string(forKey: Self.livenessKey).flatMap(LivenessMode.init(rawValue:))
            ?? (d.object(forKey: Self.requireBlinkKey) as? Bool == false ? .off : .random)
        learnFromUnlocks = UserDefaults.standard.bool(forKey: Self.learnKey)
        brightenInDark = UserDefaults.standard.bool(forKey: Self.brightenKey)
        reload()
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

    func forgetLearned() { KeychainStore.delete(account: Self.learnedAccount); learned = [] }

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
