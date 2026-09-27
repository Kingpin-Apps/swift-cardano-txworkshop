import Foundation
import Observation

/// A signing key the app holds. The secret itself (a recovery phrase or a
/// key file) is in the Keychain; this is what can be shown and matched
/// without unlocking it.
public struct StoredSigningKey: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case mnemonic, keyFile
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// The key hashes (hex) it can sign for: public, and used to match it to
    /// the signatures a transaction needs.
    public var keyHashes: [String]
    public var addedAt: Date

    public init(id: UUID = UUID(), name: String, kind: Kind, keyHashes: [String], addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.kind = kind
        self.keyHashes = keyHashes
        self.addedAt = addedAt
    }

    /// The Keychain account its secret is stored under.
    public var secretAccount: String { "signing-key-\(id.uuidString)" }
}

/// The signing keys the app holds. Secrets go to the Keychain, readable only
/// on this device and while it is unlocked; the list of keys to user
/// defaults.
@MainActor
@Observable
public final class SigningKeyStore {
    public private(set) var keys: [StoredSigningKey]
    public private(set) var lastError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let defaultsKey = "signingKeys"

    public init(
        defaults: UserDefaults = .standard,
        secrets: any SecretStore = KeychainSecretStore(service: "com.kingpinapps.txworkshop.signing-keys")
    ) {
        self.defaults = defaults
        self.secrets = secrets
        keys = defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode([StoredSigningKey].self, from: $0) } ?? []
    }

    /// Keeps `key`, with `secret` in the Keychain.
    public func add(_ key: StoredSigningKey, secret: String) throws {
        try secrets.setSecret(secret, for: key.secretAccount)
        keys.append(key)
        persist()
    }

    /// Removes `key` and its secret.
    public func remove(_ key: StoredSigningKey) {
        do {
            try secrets.removeSecret(for: key.secretAccount)
        } catch {
            lastError = String(describing: error)
        }
        keys.removeAll { $0.id == key.id }
        persist()
    }

    /// The secret for `key`. Call it only when about to sign, after the
    /// person has confirmed.
    public func secret(for key: StoredSigningKey) throws -> String? {
        try secrets.secret(for: key.secretAccount)
    }

    /// The keys that can sign for any of `keyHashes`.
    public func keys(signingFor keyHashes: Set<String>) -> [StoredSigningKey] {
        keys.filter { !keyHashes.isDisjoint(with: $0.keyHashes) }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(keys), forKey: defaultsKey)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }
}

extension SigningKeyStore {
    /// An empty store with secrets in memory, for previews and tests.
    public static func inMemory() -> SigningKeyStore {
        SigningKeyStore(defaults: UserDefaults(suiteName: "signing-keys-\(UUID().uuidString)")!, secrets: InMemorySecretStore())
    }
}
