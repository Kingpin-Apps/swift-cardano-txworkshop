import Foundation
import Security
import Synchronization

/// Somewhere to keep secrets such as API keys.
public protocol SecretStore: Sendable {
    func secret(for account: String) throws -> String?
    func setSecret(_ secret: String, for account: String) throws
    func removeSecret(for account: String) throws
}

public struct SecretStoreError: Error, Sendable, Equatable {
    public let status: OSStatus
}

/// Secrets kept as generic passwords in the Keychain, readable only while the
/// device is unlocked. With `synchronizable`, they go in iCloud Keychain, end-to-end
/// encrypted, and reach the person's other devices; otherwise they never leave
/// this one.
public struct KeychainSecretStore: SecretStore {
    public let service: String
    /// Whether new secrets are kept in iCloud Keychain.
    public let synchronizable: Bool

    public init(service: String = "com.kingpinapps.cardano-txworkshop.providers", synchronizable: Bool = false) {
        self.service = service
        self.synchronizable = synchronizable
    }

    private func query(_ account: String, dataProtection: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
            // Syncing, a secret is found whether or not it syncs yet, so ones
            // saved before syncing was turned on still are. Not syncing, only
            // this device's own copy counts: deleting a synced copy would
            // delete it on the person's other devices too.
            query[kSecAttrSynchronizable as String] = synchronizable ? kSecAttrSynchronizableAny : kCFBooleanFalse
        }
        return query
    }

    /// Runs `operation` against the data-protection keychain, or the login
    /// keychain on a Mac build signed without a team, which may not use it.
    private func withKeychain(_ operation: (Bool) -> OSStatus) -> OSStatus {
        let status = operation(true)
        #if os(macOS)
        if status == errSecMissingEntitlement { return operation(false) }
        #endif
        return status
    }

    public func secret(for account: String) throws -> String? {
        var result: AnyObject?
        let status = withKeychain { dataProtection in
            var query = query(account, dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(query as CFDictionary, &result)
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecretStoreError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        let status = withKeychain { dataProtection in
            // Replaced rather than updated, so a secret saved before syncing
            // was turned on moves to iCloud Keychain when it is next saved.
            // Not syncing, only this device's copy is replaced.
            let delete = SecItemDelete(query(account, dataProtection: dataProtection) as CFDictionary)
            guard delete == errSecSuccess || delete == errSecItemNotFound else { return delete }
            var add = query(account, dataProtection: dataProtection)
            add[kSecValueData as String] = data
            // Only the data-protection keychain can sync; the login keychain
            // fallback stays on this Mac.
            if synchronizable && dataProtection {
                add[kSecAttrSynchronizable as String] = true
                add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            } else {
                add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
            return SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError(status: status) }
    }

    public func removeSecret(for account: String) throws {
        let status = withKeychain { dataProtection in
            SecItemDelete(query(account, dataProtection: dataProtection) as CFDictionary)
        }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError(status: status) }
    }
}

/// Secrets kept in memory, for previews and tests.
public final class InMemorySecretStore: SecretStore {
    private let storage = Mutex<[String: String]>([:])

    public init(_ secrets: [String: String] = [:]) {
        storage.withLock { $0 = secrets }
    }

    public func secret(for account: String) throws -> String? { storage.withLock { $0[account] } }
    public func setSecret(_ secret: String, for account: String) throws { storage.withLock { $0[account] = secret } }
    public func removeSecret(for account: String) throws { storage.withLock { _ = $0.removeValue(forKey: account) } }
}
