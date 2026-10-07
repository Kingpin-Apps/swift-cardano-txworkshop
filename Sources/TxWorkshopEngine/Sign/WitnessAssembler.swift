import Foundation
import SwiftCardanoCore
import SwiftCDDL
import SwiftNaCl
import TxWorkshopCore

/// Adds signatures to a transaction without re-encoding anything else: the
/// body keeps its bytes (and so its id) and the rest of the witness set keeps
/// its bytes (and so its script data hash). Only the vkey witnesses entry is
/// rewritten.
public enum WitnessAssembler {
    /// `bytes` with `witnesses` added to any it already has, one per key.
    public static func merge(_ bytes: Data, adding witnesses: [VerificationKeyWitness]) throws -> Data {
        try rewrite(bytes) { existing in
            // The witnesses already there, then the new ones for keys not yet
            // signed.
            var all = existing
            var keys = Set(all.map { $0.vkey.payload })
            for witness in witnesses where keys.insert(witness.vkey.payload).inserted {
                all.append(witness)
            }
            return all
        }
    }

    /// `bytes` without the witnesses of the keys hashing to `keyHashes` (hex).
    public static func remove(_ bytes: Data, keyHashes: Set<String>) throws -> Data {
        try rewrite(bytes) { existing in
            existing.filter { witness in !((try? keyHash(witness)).map(keyHashes.contains) ?? false) }
        }
    }

    /// `bytes` with its vkey witnesses replaced by what `change` makes of them.
    static func rewrite(_ bytes: Data, _ change: ([VerificationKeyWitness]) throws -> [VerificationKeyWitness]) throws -> Data {
        let raw = [UInt8](bytes)
        let decoding = CBORNode.decodeAnnotated(raw)
        guard decoding.error == nil, let root = decoding.root, root.children.count >= 2,
            case .map? = root.children[1].node
        else { throw WitnessError.notATransaction }
        let set = root.children[1]

        let all = try change(try existing(in: bytes))

        // Every entry of the witness set but the vkey witnesses, as written.
        var entries: [ArraySlice<UInt8>] = []
        // A set tagged 258, as the Conway ledger, cardano-cli and hardware
        // wallets write it, unless the transaction already writes its
        // witnesses as a plain list. The fee was sized for the tagged form.
        var tagged = true
        for index in stride(from: 0, to: set.children.count - 1, by: 2) {
            let key = set.children[index]
            let value = set.children[index + 1]
            if case .unsigned(0)? = key.node {
                tagged = raw[value.span.start] == 0xd9
                continue
            }
            entries.append(raw[key.span.start..<value.span.end])
        }
        var newSet = header(majorType: 5, count: UInt64(entries.count + (all.isEmpty ? 0 : 1)))
        // No witnesses left: the entry goes, as an empty set may not be written.
        if !all.isEmpty {
            let list = try (tagged
                ? ListOrNonEmptyOrderedSet<VerificationKeyWitness>.nonEmptyOrderedSet(NonEmptyOrderedSet(all))
                : .list(all)).toCBORData()
            newSet += [0x00] + [UInt8](list)
        }
        for entry in entries { newSet += entry }

        return Data(raw[..<set.span.start] + newSet + raw[set.span.end...])
    }

    /// The vkey witnesses `bytes` carries.
    public static func existing(in bytes: Data) throws -> [VerificationKeyWitness] {
        (try TransactionValidation.decode(bytes)).transactionWitnessSet.vkeyWitnesses?.asList ?? []
    }

    /// A CBOR head with the shortest encoding of `count`.
    static func header(majorType: UInt8, count: UInt64) -> [UInt8] {
        let major = majorType << 5
        switch count {
        case ..<24: return [major | UInt8(count)]
        case ..<0x100: return [major | 24, UInt8(count)]
        case ..<0x10000: return [major | 25] + withUnsafeBytes(of: UInt16(count).bigEndian, Array.init)
        case ..<0x1_0000_0000: return [major | 26] + withUnsafeBytes(of: UInt32(count).bigEndian, Array.init)
        default: return [major | 27] + withUnsafeBytes(of: count.bigEndian, Array.init)
        }
    }

    /// Witnesses from text: a witness set's CBOR hex (what hardware wallets
    /// and CIP-30 wallets return), a single vkey witness's CBOR hex, or a
    /// cardano-cli witness file (`TxWitness ConwayEra`).
    public static func witnesses(from text: String) throws -> [VerificationKeyWitness] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
                let hex = object["cborHex"] as? String
            else { throw WitnessError.unreadable }
            return try witnesses(fromCBOR: try TxDocumentCodec.bytes(fromHex: hex))
        }
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: trimmed) else { throw WitnessError.unreadable }
        return try witnesses(fromCBOR: bytes)
    }

    static func witnesses(fromCBOR bytes: Data) throws -> [VerificationKeyWitness] {
        if let set = try? TransactionWitnessSet.fromCBOR(data: bytes), let vkeys = set.vkeyWitnesses?.asList, !vkeys.isEmpty {
            return vkeys
        }
        if let witness = try? VerificationKeyWitness.fromCBOR(data: bytes) {
            return [witness]
        }
        // cardano-cli: [0, [vkey, signature]] for a key witness.
        if case .list(let items)? = try? Primitive.fromCBOR(data: bytes), items.count == 2,
            let witness = try? VerificationKeyWitness(from: items[1])
        {
            return [witness]
        }
        throw WitnessError.unreadable
    }

    /// A witness's CBOR, hex, as a document keeps it.
    public static func cborHex(_ witness: VerificationKeyWitness) throws -> String {
        try witness.toCBORData().hex
    }

    /// The key hash a witness signs for.
    public static func keyHash(_ witness: VerificationKeyWitness) throws -> String {
        let key = witness.vkey.payload.prefix(32)
        return try Hash().blake2b(data: Data(key), digestSize: 28, encoder: RawEncoder.self).hex
    }

    /// Whether `witness` is a valid signature of `bytes`' transaction id.
    public static func verifies(_ witness: VerificationKeyWitness, for bytes: Data) -> Bool {
        guard let id = try? TransactionValidation.decode(bytes).id?.payload else { return false }
        let key = BIP32ED25519PublicKey(publicKey: Data(witness.vkey.payload.prefix(32)), chainCode: Data())
        return (try? key.verify(signature: witness.signature, message: id)) != nil
    }
}

public enum WitnessError: Error, Sendable, Equatable, CustomStringConvertible {
    case notATransaction
    case unreadable

    public var description: String {
        switch self {
        case .notATransaction: "The document's transaction is not a complete transaction."
        case .unreadable: "That is not a witness: paste a witness set or a witness in CBOR hex, or a cardano-cli witness file."
        }
    }
}
