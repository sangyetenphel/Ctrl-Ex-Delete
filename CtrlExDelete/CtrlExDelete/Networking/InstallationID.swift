import Foundation
import Security

/// The anonymous ID that stands in for a user account (there is no sign-up).
///
/// Created once on first launch, saved in the Keychain, and sent with every
/// request in the `X-Installation-ID` header (see docs/api.md). Because it is
/// in the Keychain, it stays the same across launches and app updates.
enum InstallationID {
    private static let service = "com.ctrlexdelete.installation"
    private static let account = "installation-id"

    /// Cached after the first read so the Keychain is only touched once per launch.
    static let current: UUID = loadOrCreate()

    private static func loadOrCreate() -> UUID {
        if let saved = load() {
            return saved
        }
        let newID = UUID()
        save(newID)
        return newID
    }

    private static func load() -> UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return UUID(uuidString: text)
    }

    private static func save(_ id: UUID) {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var item = key
        item[kSecValueData as String] = Data(id.uuidString.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(key as CFDictionary)
        SecItemAdd(item as CFDictionary, nil)
    }
}
