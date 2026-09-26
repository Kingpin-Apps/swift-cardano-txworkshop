import Foundation

/// Everything a Tx Workshop document holds.
///
/// A document is one transaction and the work around it: the bytes as they
/// were written, the chain data needed to validate it again offline, notes, the
/// witnesses collected for it so far, and the history of validation runs.
/// Opening a bare `.tx` or `.cbor` file fills in the transaction alone.
public struct TxDocumentContent: Sendable, Equatable {
    /// The transaction's CBOR, exactly as written, or `nil` for a new, empty
    /// document.
    public var transaction: Data?
    /// The text envelope the transaction came in, if it came in one.
    public var envelope: TextEnvelopeInfo?
    public var notes: String
    /// The network the transaction is for, when known.
    public var network: CardanoNetwork?
    /// Chain data resolved for the transaction, kept so it can be validated
    /// again without a connection.
    public var chainContext: ChainContextSnapshot?
    /// Witnesses collected for the transaction, for multi-signature work.
    public var witnesses: [CollectedWitness]
    /// Past validation runs, oldest first.
    public var validations: [ValidationRecord]

    public init(
        transaction: Data? = nil,
        envelope: TextEnvelopeInfo? = nil,
        notes: String = "",
        network: CardanoNetwork? = nil,
        chainContext: ChainContextSnapshot? = nil,
        witnesses: [CollectedWitness] = [],
        validations: [ValidationRecord] = []
    ) {
        self.transaction = transaction
        self.envelope = envelope
        self.notes = notes
        self.network = network
        self.chainContext = chainContext
        self.witnesses = witnesses
        self.validations = validations
    }

    /// Whether the document has no transaction yet.
    public var isEmpty: Bool { transaction == nil }
}

/// The `type` and `description` of a cardano-cli text envelope.
public struct TextEnvelopeInfo: Codable, Sendable, Equatable {
    public var type: String
    public var description: String

    public init(type: String, description: String) {
        self.type = type
        self.description = description
    }
}

/// A Cardano network.
public enum CardanoNetwork: Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case mainnet
    case preprod
    case preview
    /// Any other network, by its magic number.
    case custom(magic: UInt32)

    public static let allCases: [CardanoNetwork] = [.mainnet, .preprod, .preview]

    public var id: String {
        switch self {
        case .mainnet: "mainnet"
        case .preprod: "preprod"
        case .preview: "preview"
        case .custom(let magic): "custom-\(magic)"
        }
    }

    /// The network magic.
    public var magic: UInt32 {
        switch self {
        case .mainnet: 764_824_073
        case .preprod: 1
        case .preview: 2
        case .custom(let magic): magic
        }
    }

    public var name: LocalizedStringResource {
        switch self {
        case .mainnet: LocalizedStringResource("Mainnet", bundle: #bundle)
        case .preprod: LocalizedStringResource("Preprod", bundle: #bundle)
        case .preview: LocalizedStringResource("Preview", bundle: #bundle)
        case .custom(let magic): LocalizedStringResource("Custom (\(magic))", bundle: #bundle)
        }
    }
}

/// Chain data resolved for a transaction.
public struct ChainContextSnapshot: Codable, Sendable, Equatable {
    /// When the data was fetched.
    public var fetchedAt: Date
    /// Every input the transaction spends or references, as UTxO CBOR in hex.
    public var utxos: [String]
    /// The inputs, as `<transaction id>#<index>`, that were already spent
    /// when the data was fetched.
    public var spentInputs: [String]?
    /// Token names from the token registry (CIP-26).
    public var tokens: [TokenInfo]?
    /// The protocol parameters, as the provider returned them (JSON).
    public var protocolParameters: Data?
    /// The chain tip slot at the time.
    public var tipSlot: UInt64?

    public init(
        fetchedAt: Date,
        utxos: [String],
        spentInputs: [String]? = nil,
        tokens: [TokenInfo]? = nil,
        protocolParameters: Data? = nil,
        tipSlot: UInt64? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.utxos = utxos
        self.spentInputs = spentInputs
        self.tokens = tokens
        self.protocolParameters = protocolParameters
        self.tipSlot = tipSlot
    }
}

/// What the token registry says about one asset.
public struct TokenInfo: Codable, Sendable, Equatable {
    /// The policy id and asset name, in hex, run together.
    public var subject: String
    public var name: String?
    public var ticker: String?
    public var decimals: Int?

    public init(subject: String, name: String? = nil, ticker: String? = nil, decimals: Int? = nil) {
        self.subject = subject
        self.name = name
        self.ticker = ticker
        self.decimals = decimals
    }
}

/// A witness collected for the transaction.
public struct CollectedWitness: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Who the witness is from, as the person labelled it.
    public var label: String
    /// The verification key hash it signs for, hex.
    public var keyHash: String
    /// The witness set CBOR, hex.
    public var witnessCBOR: String
    public var addedAt: Date

    public init(id: UUID = UUID(), label: String, keyHash: String, witnessCBOR: String, addedAt: Date) {
        self.id = id
        self.label = label
        self.keyHash = keyHash
        self.witnessCBOR = witnessCBOR
        self.addedAt = addedAt
    }
}

/// The outcome of one validation run.
public struct ValidationRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var ranAt: Date
    public var errorCount: Int
    public var warningCount: Int
    /// The full report, JSON.
    public var report: Data?

    public init(id: UUID = UUID(), ranAt: Date, errorCount: Int, warningCount: Int, report: Data? = nil) {
        self.id = id
        self.ranAt = ranAt
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.report = report
    }

    public var passed: Bool { errorCount == 0 }
}
