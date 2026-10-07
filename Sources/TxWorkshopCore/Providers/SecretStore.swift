import Foundation
import Security
import Synchronization

/// Somewhere to keep secrets such as API keys.
public protocol SecretStore: Sendable {
    func secret(for account: String) throws -> String?
    func setSecret(_ secret: String, for account: String) throws
    func removeSecret(for account: String) throws
}

public struct SecretStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    public let status: OSStatus

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"
        return "\(message) (\(status))"
    }
}

/// Where in the Keychain a secret is kept.
public enum KeychainPlace: Sendable, Hashable, CaseIterable {
    /// The data-protection keychain, on this device only.
    case local
    /// The data-protection keychain, in iCloud Keychain: end-to-end encrypted,
    /// and on the person's other devices too.
    case synced
    /// The Mac's login keychain: where a build signed without a team must keep
    /// secrets, since only a team-signed app may use the data-protection
    /// keychain.
    case login
}

/// The Keychain calls ``KeychainSecretStore`` makes, so its choices can be
/// tested without the real Keychain.
public protocol KeychainBackend: Sendable {
    /// The secret at `place`, or nil when there is none; a failed status otherwise.
    func read(account: String, service: String, place: KeychainPlace) -> Result<Data?, SecretStoreError>
    /// Adds the secret at `place`, or replaces the one already there.
    func write(_ data: Data, account: String, service: String, place: KeychainPlace) -> OSStatus
    func delete(account: String, service: String, place: KeychainPlace) -> OSStatus
}

/// Secrets kept as generic passwords in the Keychain, readable only while the
/// device is unlocked. With `synchronizable`, they go in iCloud Keychain, end-to-end
/// encrypted, and reach the person's other devices; otherwise they never leave
/// this one.
///
/// A secret is never deleted before its replacement is safely written: it is
/// replaced in place, and copies elsewhere are removed only once the new one is
/// stored. When iCloud Keychain refuses a secret, as it does a build not entitled
/// to it, the secret is kept on this device instead. A build signed without a
/// team, which may not use the data-protection keychain at all, keeps its
/// secrets in the Mac's login keychain.
public struct KeychainSecretStore: SecretStore {
    public let service: String
    /// Whether new secrets are kept in iCloud Keychain.
    public let synchronizable: Bool
    private let keychain: any KeychainBackend

    public init(
        service: String = "com.kingpinapps.cardano-txworkshop.providers", synchronizable: Bool = false,
        keychain: any KeychainBackend = SystemKeychain()
    ) {
        self.service = service
        self.synchronizable = synchronizable
        self.keychain = keychain
    }

    /// The data-protection places, the one this store saves to first. Both are
    /// read: a secret saved before syncing was turned on, or synced from another
    /// device before it was turned off, is still found.
    private var dataProtectionPlaces: [KeychainPlace] {
        synchronizable ? [.synced, .local] : [.local, .synced]
    }

    public func secret(for account: String) throws -> String? {
        var dataProtectionAvailable = true
        places: for place in dataProtectionPlaces {
            switch keychain.read(account: account, service: service, place: place) {
            case .success(let data?):
                return String(decoding: data, as: UTF8.self)
            case .success(nil):
                continue
            case .failure where place == .synced:
                // iCloud Keychain can be out of reach on its own; this
                // device's copy may still be there.
                continue
            case .failure(let error) where error.status == errSecMissingEntitlement:
                dataProtectionAvailable = false
                break places
            case .failure(let error):
                throw error
            }
        }
        #if os(macOS)
        switch keychain.read(account: account, service: service, place: .login) {
        case .success(let data?):
            let secret = String(decoding: data, as: UTF8.self)
            if dataProtectionAvailable {
                // An earlier build kept it in the login keychain: move it, and
                // remove the old copy only once the new one is stored there.
                if let place = try? store(data, for: account), place != .login {
                    _ = keychain.delete(account: account, service: service, place: .login)
                }
            }
            return secret
        case .success(nil):
            return nil
        case .failure(let error):
            throw error
        }
        #else
        return nil
        #endif
    }

    public func setSecret(_ secret: String, for account: String) throws {
        let place = try store(Data(secret.utf8), for: account)
        // Now that it is stored, copies elsewhere would only shadow it. A synced
        // copy stays when this store does not sync: removing it would remove it
        // from the person's other devices too.
        var stale: [KeychainPlace] = []
        switch place {
        case .synced: stale = [.local, .login]
        case .local: stale = [.login]
        case .login: stale = []
        }
        #if !os(macOS)
        stale.removeAll { $0 == .login }
        #endif
        for other in stale {
            _ = keychain.delete(account: account, service: service, place: other)
        }
    }

    /// Writes `data` where this store keeps secrets, and says where it went:
    /// iCloud Keychain when syncing and allowed, else this device's
    /// data-protection keychain, else, on a Mac build that may not use that,
    /// the login keychain.
    private func store(_ data: Data, for account: String) throws -> KeychainPlace {
        var failure: OSStatus = errSecSuccess
        var dataProtectionAvailable = true
        for place in synchronizable ? [KeychainPlace.synced, .local] : [.local] {
            let status = keychain.write(data, account: account, service: service, place: place)
            if status == errSecSuccess { return place }
            // iCloud Keychain can be refused on its own; only this device's
            // keychain refusing means the data-protection keychain is out of reach.
            if place == .local && status == errSecMissingEntitlement { dataProtectionAvailable = false }
            failure = status
        }
        #if os(macOS)
        if !dataProtectionAvailable {
            let status = keychain.write(data, account: account, service: service, place: .login)
            if status == errSecSuccess { return .login }
            failure = status
        }
        #endif
        throw SecretStoreError(status: failure)
    }

    public func removeSecret(for account: String) throws {
        // Syncing, the secret goes from every device; not syncing, only this one's.
        var places: [KeychainPlace] = synchronizable ? [.synced, .local] : [.local]
        #if os(macOS)
        places.append(.login)
        #endif
        for place in places {
            let status = keychain.delete(account: account, service: service, place: place)
            guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement else {
                throw SecretStoreError(status: status)
            }
        }
    }
}

/// The system Keychain.
public struct SystemKeychain: KeychainBackend {
    public init() {}

    private func query(account: String, service: String, place: KeychainPlace) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        switch place {
        case .local:
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse
        case .synced:
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        case .login:
            // The file-based keychain: no data-protection flag, and it never syncs.
            break
        }
        return query
    }

    public func read(account: String, service: String, place: KeychainPlace) -> Result<Data?, SecretStoreError> {
        var query = query(account: account, service: service, place: place)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return .success(result as? Data)
        case errSecItemNotFound: return .success(nil)
        default: return .failure(SecretStoreError(status: status))
        }
    }

    public func write(_ data: Data, account: String, service: String, place: KeychainPlace) -> OSStatus {
        let match = query(account: account, service: service, place: place)
        // Replaced in place when it exists, so a failure leaves the old value.
        let update = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard update == errSecItemNotFound else { return update }
        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = place == .synced
            ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }

    public func delete(account: String, service: String, place: KeychainPlace) -> OSStatus {
        SecItemDelete(query(account: account, service: service, place: place) as CFDictionary)
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
