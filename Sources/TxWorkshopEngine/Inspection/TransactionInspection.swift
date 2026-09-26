import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import SwiftCardanoUPLC
import TxWorkshopCore

/// Everything the inspector shows about one transaction.
public struct TransactionInspection: Sendable, Equatable {
    public let summary: TransactionSummary
    public let inputs: [InputDetail]
    public let referenceInputs: [InputDetail]
    public let collateralInputs: [InputDetail]
    public let outputs: [OutputDetail]
    public let collateralReturn: OutputDetail?
    public let mint: [AssetDetail]
    public let validity: ValidityWindow
    public let scripts: [ScriptDetail]
    public let redeemers: [RedeemerDetail]
    public let datums: [DatumDetail]
    public let metadata: [MetadataEntry]
    public let requiredSigners: [String]

    public var view: TransactionView { summary.view }
}

public struct InputDetail: Sendable, Equatable, Identifiable {
    public let transactionID: String
    public let index: UInt16
    public var id: String { "\(transactionID)#\(index)" }
}

/// An output, as the chain would read it.
public struct OutputDetail: Sendable, Equatable, Identifiable {
    public let index: Int
    public let address: AddressDetail
    public let lovelace: Int64
    public let assets: [AssetDetail]
    public let datum: DatumReference?
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
    public var id: String { "\(policyID).\(assetNameHex)" }
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
    public let tree: DataNode
    public var id: Int { view.position }
}

public struct DatumDetail: Sendable, Equatable, Identifiable {
    public let hash: String
    public let tree: DataNode
    public let cborHex: String
    public var id: String { hash }
}

/// One metadata label and its value.
public struct MetadataEntry: Sendable, Equatable, Identifiable {
    public let label: UInt64
    /// What the label is registered for (CIP-10), when known.
    public let registeredAs: String?
    public let tree: DataNode
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
