import Foundation
import SwiftCardanoCore
import SwiftNaCl
import TxWorkshopCore

/// Secret key material the app keeps in the Keychain.
public enum SigningKeyMaterial: Sendable, Equatable {
    /// A BIP-39 recovery phrase, with its optional passphrase.
    case mnemonic(words: String, passphrase: String)
    /// A cardano-cli signing key text envelope (`.skey`).
    case envelope(json: String)
}

/// The signing keys one piece of key material holds, by the key hash each
/// signs for.
public struct KeyRing: Sendable {
    /// Key hash (hex) to key.
    let keys: [String: SigningKeyType]
    /// Where each mnemonic key was derived, by key hash: `1852H/1815H/0H/0/3`.
    public let paths: [String: String]

    public var keyHashes: Set<String> { Set(keys.keys) }

    /// How many addresses of each chain a mnemonic is searched for keys.
    public static let addressGap = 20

    /// Loads `material`. A mnemonic's keys are derived for `accounts`: the
    /// first ``addressGap`` external and change payment keys, and the stake
    /// and DRep keys.
    public init(_ material: SigningKeyMaterial, accounts: Range<Int> = 0..<1) throws {
        switch material {
        case .mnemonic(let words, let passphrase):
            let wallet: HDWallet
            do {
                wallet = try HDWallet.fromMnemonic(mnemonic: words.trimmingCharacters(in: .whitespacesAndNewlines), passphrase: passphrase)
            } catch {
                throw KeyRingError.badMnemonic
            }
            var keys: [String: SigningKeyType] = [:]
            var paths: [String: String] = [:]
            for account in accounts {
                var derivations: [(role: Int, index: Int)] = []
                for index in 0..<Self.addressGap { derivations += [(0, index), (1, index)] }
                derivations += [(2, 0), (3, 0)]
                for (role, index) in derivations {
                    let path = "m/1852'/1815'/\(account)'/\(role)/\(index)"
                    let child = try wallet.derive(fromPath: path)
                    let key = SigningKeyType.extendedSigningKey(PaymentExtendedSigningKey(
                        payload: child.xPrivateKey + child.publicKey + child.chainCode,
                        type: PaymentExtendedSigningKey.TYPE, description: PaymentExtendedSigningKey.DESCRIPTION
                    ))
                    let hash = try Self.keyHash(key)
                    keys[hash] = key
                    paths[hash] = "1852H/1815H/\(account)H/\(role)/\(index)"
                }
            }
            self.keys = keys
            self.paths = paths
        case .envelope(let json):
            let key = try Self.envelopeKey(json)
            keys = [try Self.keyHash(key): key]
            paths = [:]
        }
    }

    /// The key hash a signing key signs for.
    static func keyHash(_ key: SigningKeyType) throws -> String {
        // Blake2b-224 of the 32-byte Ed25519 key; an extended key's chain
        // code is not part of it.
        let vkey = try key.toVerificationKeyType().payload.prefix(32)
        return try Hash().blake2b(data: Data(vkey), digestSize: 28, encoder: RawEncoder.self).hex
    }

    static func envelopeKey(_ json: String) throws -> SigningKeyType {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let type = object["type"] as? String
        else { throw KeyRingError.badEnvelope("That is not a text envelope.") }
        do {
            if type.contains("Extended") {
                return .extendedSigningKey(try PaymentExtendedSigningKey.fromTextEnvelope(json))
            }
            if type.contains("SigningKey") {
                return .signingKey(try PaymentSigningKey.fromTextEnvelope(json))
            }
        } catch {
            throw KeyRingError.badEnvelope("The key does not load: \(error)")
        }
        throw KeyRingError.badEnvelope("A \(type) is not a signing key.")
    }

    /// Witnesses for every key in `needed` this ring holds, signing the
    /// transaction id of `bytes` (the hash of the body as written).
    public func witnesses(for bytes: Data, needed: Set<String>) throws -> [VerificationKeyWitness] {
        let transaction = try TransactionValidation.decode(bytes)
        guard let id = transaction.id?.payload else { throw KeyRingError.noTransactionID }
        return try needed.sorted().compactMap { hash in
            guard let key = keys[hash] else { return nil }
            return VerificationKeyWitness(vkey: try key.toVerificationKeyType(), signature: try key.sign(data: id))
        }
    }
}

public enum KeyRingError: Error, Sendable, Equatable, CustomStringConvertible {
    case badMnemonic
    case badEnvelope(String)
    case noTransactionID

    public var description: String {
        switch self {
        case .badMnemonic: "That is not a valid recovery phrase."
        case .badEnvelope(let reason): reason
        case .noTransactionID: "The transaction has no id to sign."
        }
    }
}
