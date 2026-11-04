import Foundation
import OSLog
import Security

/// The anonymous ID that stands in for a user account (there is no sign-up).
///
/// Created once on first launch, saved in the Keychain, and sent with every
/// request in the `X-Installation-ID` header (see docs/api.md). Because it is
/// in the Keychain, it stays the same across launches, force-closes and app
/// updates.
///
/// A new ID is made ONLY when the Keychain says there is none. If the
/// Keychain can't be read (e.g. the phone hasn't been unlocked since it
/// restarted), `current()` throws instead, so a temporary problem never
/// replaces the user's ID and hides their progress.
enum InstallationID {
    private static let service = "com.ctrlexdelete.installation"
    private static let account = "installation-id"
    private static var cached: UUID?

    enum Failure: LocalizedError {
        case keychainUnavailable(OSStatus)

        var errorDescription: String? {
            "Your saved progress couldn\u{2019}t be opened yet. Unlock your iPhone and try again."
        }
    }

    /// Read from the Keychain once, then kept for the rest of the launch.
    static func current() throws -> UUID {
        if let cached { return cached }
        let id = try loadOrCreate()
        cached = id
        #if DEBUG
        Logger(subsystem: "CtrlExDelete", category: "installation")
            .info("Installation ID: \(id.uuidString, privacy: .private)")
        #endif
        return id
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func loadOrCreate() throws -> UUID {
        if let saved = try load() {
            return saved
        }
        let newID = UUID()
        var item = baseQuery
        item[kSecValueData as String] = Data(newID.uuidString.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        switch SecItemAdd(item as CFDictionary, nil) {
        case errSecSuccess:
            return newID
        case errSecDuplicateItem:
            // Saved meanwhile: use that one, never overwrite it.
            if let saved = try load() { return saved }
            throw Failure.keychainUnavailable(errSecDuplicateItem)
        case let status:
            throw Failure.keychainUnavailable(status)
        }
    }

    /// nil only when there is no saved ID; any other Keychain error throws.
    private static func load() throws -> UUID? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let text = String(data: data, encoding: .utf8),
                  let id = UUID(uuidString: text) else {
                throw Failure.keychainUnavailable(errSecDecode)
            }
            return id
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychainUnavailable(status)
        }
    }
}
