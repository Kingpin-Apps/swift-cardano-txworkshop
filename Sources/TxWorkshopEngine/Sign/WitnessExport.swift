import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// Witnesses written out for whoever assembles the transaction: as the
/// cardano-cli witness file `transaction assemble --witness-file` reads, or as
/// CBOR.
public enum WitnessExport {
    /// The ways a witness is written.
    public enum Format: String, Sendable, CaseIterable, Identifiable {
        /// A cardano-cli text envelope (`TxWitness ConwayEra`), `.witness`.
        case textEnvelope
        /// The `[vkey, signature]` CBOR, `.cbor`.
        case cbor
        /// The same CBOR as hex text, `.hex`.
        case hex

        public var id: Self { self }

        public var fileExtension: String {
            switch self {
            case .textEnvelope: "witness"
            case .cbor: "cbor"
            case .hex: "hex"
            }
        }
    }

    /// The witness a collected record holds.
    public static func witness(_ record: CollectedWitness) throws -> VerificationKeyWitness {
        try VerificationKeyWitness.fromCBOR(data: try TxDocumentCodec.bytes(fromHex: record.witnessCBOR))
    }

    /// `witness` as a file in `format`. The text envelope's `cborHex` is the
    /// bare `[vkey, signature]`, as cardano-cli 10 and later write it.
    public static func file(_ witness: VerificationKeyWitness, format: Format) throws -> Data {
        switch format {
        case .textEnvelope:
            guard let json = try witness.toTextEnvelope() else { throw WitnessError.unreadable }
            return Data((json + "\n").utf8)
        case .cbor:
            return try witness.toCBORData()
        case .hex:
            return Data((try witness.toCBORData().hex + "\n").utf8)
        }
    }

    /// Every witness as one witness set, CBOR hex: what CIP-30 wallets'
    /// `signTx` returns, and what TxWorkshop's Add Witness takes back.
    public static func witnessSetHex(_ witnesses: [VerificationKeyWitness]) throws -> String {
        var set = TransactionWitnessSet()
        set.vkeyWitnesses = .nonEmptyOrderedSet(NonEmptyOrderedSet(witnesses))
        return try set.toCBORData().hex
    }

    /// `bytes` with no key witnesses: the same body, so the same id, for
    /// `transaction assemble --tx-body-file` with every witness file beside it.
    public static func unsigned(_ bytes: Data) throws -> Data {
        let all = try WitnessAssembler.existing(in: bytes).map(WitnessAssembler.keyHash)
        return all.isEmpty ? bytes : try WitnessAssembler.remove(bytes, keyHashes: Set(all))
    }

    /// A file name from who the witness is from: `alice.witness`, the name
    /// Add Witness gives back to it.
    public static func fileName(for label: String) -> String {
        let cleaned = label
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "witness" : cleaned
    }
}
