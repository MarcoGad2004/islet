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
    private static let passwordAccount = "login-password"
    private static let thresholdKey = "faceUnlockThreshold"

    private(set) var embeddings: [[Float]] = []
    private(set) var hasPassword = false
    /// Cosine-similarity score a probe needs to count as a match. Tune with "Test recognition".
    var threshold: Float {
        didSet { UserDefaults.standard.set(threshold, forKey: Self.thresholdKey) }
    }

    var isEnrolled: Bool { !embeddings.isEmpty }
    var isReady: Bool { isEnrolled && hasPassword }

    init() {
        let t = UserDefaults.standard.float(forKey: Self.thresholdKey)
        threshold = t > 0 ? t : 0.45
        reload()
    }

    func reload() {
        if let data = KeychainStore.load(account: Self.facesAccount),
           let list = try? JSONDecoder().decode([[Float]].self, from: data) { embeddings = list } else { embeddings = [] }
        hasPassword = KeychainStore.load(account: Self.passwordAccount) != nil
    }

    func saveEmbeddings(_ list: [[Float]]) -> Bool {
        guard let data = try? JSONEncoder().encode(list), KeychainStore.save(data, account: Self.facesAccount) else { return false }
        embeddings = list
        return true
    }

    func savePassword(_ password: String) -> Bool {
        let ok = KeychainStore.save(Data(password.utf8), account: Self.passwordAccount)
        hasPassword = ok || hasPassword
        return ok
    }

    /// The stored login password, for the unlock service only.
    func password() -> String? { KeychainStore.load(account: Self.passwordAccount).flatMap { String(data: $0, encoding: .utf8) } }

    func removeFace() { KeychainStore.delete(account: Self.facesAccount); embeddings = [] }
    func removePassword() { KeychainStore.delete(account: Self.passwordAccount); hasPassword = false }
    func removeAll() { removeFace(); removePassword() }
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
