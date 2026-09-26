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
/// device is unlocked and never synced off it.
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "com.kingpinapps.txworkshop.providers") {
        self.service = service
    }

    private func query(_ account: String, dataProtection: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
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
            let update = SecItemUpdate(
                query(account, dataProtection: dataProtection) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard update == errSecItemNotFound else { return update }
            var add = query(account, dataProtection: dataProtection)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
