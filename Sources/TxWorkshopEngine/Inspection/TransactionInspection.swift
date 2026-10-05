import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import SwiftCardanoUPLC
import TxWorkshopCore

/// Everything the inspector shows about one transaction.
public struct TransactionInspection: Sendable, Equatable {
    public let summary: TransactionSummary
    public internal(set) var inputs: [InputDetail]
    public internal(set) var referenceInputs: [InputDetail]
    public internal(set) var collateralInputs: [InputDetail]
    public internal(set) var outputs: [OutputDetail]
    public internal(set) var collateralReturn: OutputDetail?
    public let mint: [AssetDetail]
    public let validity: ValidityWindow
    public let scripts: [ScriptDetail]
    public internal(set) var redeemers: [RedeemerDetail]
    public internal(set) var datums: [DatumDetail]
    public let metadata: [MetadataEntry]
    public let requiredSigners: [String]
    /// The key hashes of the keys that signed, from the vkey witnesses.
    public let signers: [String]

    public var view: TransactionView { summary.view }
}

public struct InputDetail: Sendable, Equatable, Identifiable {
    public let transactionID: String
    public let index: UInt16
    /// What the chain said about the input, when it was looked up.
    public let status: Status
    /// The output the input spends, when it was looked up and found.
    public internal(set) var output: OutputDetail?
    public var id: String { "\(transactionID)#\(index)" }

    public enum Status: Sendable, Equatable {
        /// Not looked up yet.
        case unresolved
        case unspent
        case spent
        /// The provider did not know it; some providers only see unspent
        /// outputs, so it may be spent.
        case notFound
    }
}

/// An output, as the chain would read it.
public struct OutputDetail: Sendable, Equatable, Identifiable {
    public let index: Int
    public let address: AddressDetail
    public let lovelace: Int64
    public let assets: [AssetDetail]
    public internal(set) var datum: DatumReference?
    public let referenceScript: ScriptDetail?
    public var id: Int { index }
}

public struct AddressDetail: Sendable, Equatable {
    /// Bech32, or Base58 for Byron addresses, or hex.
    public let text: String
    public let kind: Kind
    /// The payment credential, `key:<hash>` or `script:<hash>`.
    public let payment: String?
    /// The stake credential or pointer, if any.
    public let stake: String?
    public let isMainnet: Bool

    public enum Kind: String, Sendable, Equatable {
        case base, pointer, enterprise, reward, byron, unknown
    }

    public var paysToScript: Bool { payment?.hasPrefix("script:") ?? false }
}

/// A native asset quantity. Negative in `mint` when burning.
public struct AssetDetail: Sendable, Equatable, Identifiable {
    public let policyID: String
    public let assetNameHex: String
    /// The asset name as text, when it is printable UTF-8.
    public let assetName: String?
    public let fingerprint: String?
    public let quantity: Int64
    /// A name from CIP-25 metadata or the token registry.
    public let displayName: String?
    public let nameSource: NameSource?
    public let ticker: String?
    /// How many decimal places the registry says the quantity has.
    public let decimals: Int?
    public var id: String { "\(policyID).\(assetNameHex)" }
    /// How the token registry names the asset.
    public var registrySubject: String { policyID + assetNameHex }

    public enum NameSource: Sendable, Equatable {
        /// The transaction's own NFT metadata (label 721).
        case cip25
        /// The Cardano token registry.
        case registry
    }
    /// CIP-67 label, when the name carries one (e.g. 222 for CIP-68 NFTs).
    public var cip67Label: Int? { AssetDetail.cip67Label(ofNameHex: assetNameHex) }

    static func cip67Label(ofNameHex hex: String) -> Int? {
        // A CIP-67 prefix is 4 bytes: 0000 + label (16 bits) + checksum (8 bits), 0 nibble last.
        guard hex.count >= 8, hex.hasPrefix("0"), hex.dropFirst(7).first == "0" else { return nil }
        let middle = hex.dropFirst(1).prefix(4)
        return Int(middle, radix: 16)
    }
}

public enum DatumReference: Sendable, Equatable {
    case hash(String)
    case inline(hash: String, tree: DataNode, cborHex: String)
}

public struct ScriptDetail: Sendable, Equatable, Identifiable {
    public let hash: String
    public let language: String
    public let size: Int
    /// Pretty-printed UPLC for Plutus scripts, or the native script's rules.
    public let listing: String?
    public var id: String { hash }
}

public struct RedeemerDetail: Sendable, Equatable, Identifiable {
    public let view: RedeemerView
    public internal(set) var tree: DataNode
    public var id: Int { view.position }
}

public struct DatumDetail: Sendable, Equatable, Identifiable {
    public let hash: String
    public internal(set) var tree: DataNode
    public let cborHex: String
    public var id: String { hash }
}

/// One metadata label and its value.
public struct MetadataEntry: Sendable, Equatable, Identifiable {
    public let label: UInt64
    /// What the label is registered for (CIP-10), when known.
    public let registeredAs: String?
    public internal(set) var tree: DataNode
    /// The CIP-20 message, for label 674.
    public let message: String?
    public var id: UInt64 { label }
}

/// The slots a transaction may be included in, and their times when the
/// network's slot timeline is known.
public struct ValidityWindow: Sendable, Equatable {
    public let startSlot: UInt64?
    public let endSlot: UInt64?
    public let start: Date?
    public let end: Date?

    public var isUnbounded: Bool { startSlot == nil && endSlot == nil }
}
