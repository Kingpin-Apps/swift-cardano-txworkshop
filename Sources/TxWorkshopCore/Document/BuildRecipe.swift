import Foundation

/// What the builder is asked to make: the form behind a built transaction,
/// kept in the document so it can be changed and built again.
public struct BuildRecipe: Codable, Sendable, Equatable {
    /// Watch-only addresses whose UTxOs the builder may spend.
    public var sourceAddresses: [String]
    /// UTxOs the builder may spend, as CBOR hex: pasted, or fetched from
    /// ``sourceAddresses``.
    public var utxos: [String]
    /// Inputs (`<transaction id>#<index>`) to spend whatever coin selection
    /// picks.
    public var fixedInputs: [String]
    public var outputs: [OutputDraft]
    /// Where change goes; the first source address when empty.
    public var changeAddress: String
    public var coinSelection: CoinSelection
    /// Slots the transaction is valid from and until; `nil` leaves them open,
    /// or to the builder's defaults when scripts run.
    public var validFrom: UInt64?
    public var validUntil: UInt64?
    /// A CIP-20 message, one line per line.
    public var message: String
    /// Key hashes (hex) that must sign.
    public var requiredSigners: [String]
    /// Lovelace added to the computed fee.
    public var feeBuffer: UInt64?
    /// Assets to mint (positive) or burn (negative), by policy script.
    public var mints: [MintDraft]
    /// Script-locked UTxOs to spend, with what unlocks them.
    public var scriptInputs: [ScriptInputDraft]
    /// Inputs (`<transaction id>#<index>`) to put up as collateral; the
    /// builder picks from the source addresses when empty.
    public var collateral: [String]
    public var certificates: [CertificateItem]
    public var withdrawals: [WithdrawalDraft]
    public var votes: [VoteDraft]
    public var proposals: [ProposalDraft]
    /// Lovelace given to the treasury.
    public var donation: UInt64?
    /// The CIP-57 blueprints the recipe's forms use, kept with the document.
    public var blueprints: [StoredBlueprint]

    public enum CoinSelection: String, Codable, Sendable, CaseIterable {
        case randomImprove, largestFirst
    }

    public init(
        sourceAddresses: [String] = [], utxos: [String] = [], fixedInputs: [String] = [], outputs: [OutputDraft] = [],
        changeAddress: String = "", coinSelection: CoinSelection = .randomImprove, validFrom: UInt64? = nil,
        validUntil: UInt64? = nil, message: String = "", requiredSigners: [String] = [], feeBuffer: UInt64? = nil,
        mints: [MintDraft] = [], scriptInputs: [ScriptInputDraft] = [], collateral: [String] = [],
        certificates: [CertificateItem] = [], withdrawals: [WithdrawalDraft] = [], votes: [VoteDraft] = [],
        proposals: [ProposalDraft] = [], donation: UInt64? = nil, blueprints: [StoredBlueprint] = []
    ) {
        self.sourceAddresses = sourceAddresses
        self.utxos = utxos
        self.fixedInputs = fixedInputs
        self.outputs = outputs
        self.changeAddress = changeAddress
        self.coinSelection = coinSelection
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.message = message
        self.requiredSigners = requiredSigners
        self.feeBuffer = feeBuffer
        self.mints = mints
        self.scriptInputs = scriptInputs
        self.collateral = collateral
        self.certificates = certificates
        self.withdrawals = withdrawals
        self.votes = votes
        self.proposals = proposals
        self.donation = donation
        self.blueprints = blueprints
    }

    /// Reads recipes saved before a field existed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceAddresses = try c.decodeIfPresent([String].self, forKey: .sourceAddresses) ?? []
        utxos = try c.decodeIfPresent([String].self, forKey: .utxos) ?? []
        fixedInputs = try c.decodeIfPresent([String].self, forKey: .fixedInputs) ?? []
        outputs = try c.decodeIfPresent([OutputDraft].self, forKey: .outputs) ?? []
        changeAddress = try c.decodeIfPresent(String.self, forKey: .changeAddress) ?? ""
        coinSelection = try c.decodeIfPresent(CoinSelection.self, forKey: .coinSelection) ?? .randomImprove
        validFrom = try c.decodeIfPresent(UInt64.self, forKey: .validFrom)
        validUntil = try c.decodeIfPresent(UInt64.self, forKey: .validUntil)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        requiredSigners = try c.decodeIfPresent([String].self, forKey: .requiredSigners) ?? []
        feeBuffer = try c.decodeIfPresent(UInt64.self, forKey: .feeBuffer)
        mints = try c.decodeIfPresent([MintDraft].self, forKey: .mints) ?? []
        scriptInputs = try c.decodeIfPresent([ScriptInputDraft].self, forKey: .scriptInputs) ?? []
        collateral = try c.decodeIfPresent([String].self, forKey: .collateral) ?? []
        certificates = try c.decodeIfPresent([CertificateItem].self, forKey: .certificates) ?? []
        withdrawals = try c.decodeIfPresent([WithdrawalDraft].self, forKey: .withdrawals) ?? []
        votes = try c.decodeIfPresent([VoteDraft].self, forKey: .votes) ?? []
        proposals = try c.decodeIfPresent([ProposalDraft].self, forKey: .proposals) ?? []
        donation = try c.decodeIfPresent(UInt64.self, forKey: .donation)
        blueprints = try c.decodeIfPresent([StoredBlueprint].self, forKey: .blueprints) ?? []
    }
}

/// One output to create.
public struct OutputDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var address: String
    /// Lovelace to send; `nil` sends the least the ledger allows.
    public var lovelace: UInt64?
    public var assets: [AssetDraft]
    public var datum: DatumDraft
    /// A reference script to carry, as script CBOR hex.
    public var referenceScript: String?
    /// The inline datum's blueprint form, when it is filled in through one.
    public var datumForm: BlueprintForm?

    public init(
        id: UUID = UUID(), address: String = "", lovelace: UInt64? = nil, assets: [AssetDraft] = [],
        datum: DatumDraft = .none, referenceScript: String? = nil, datumForm: BlueprintForm? = nil
    ) {
        self.id = id
        self.address = address
        self.lovelace = lovelace
        self.assets = assets
        self.datum = datum
        self.referenceScript = referenceScript
        self.datumForm = datumForm
    }
}

/// A quantity of one native asset.
public struct AssetDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var policyID: String
    public var assetNameHex: String
    public var quantity: Int64

    public init(id: UUID = UUID(), policyID: String = "", assetNameHex: String = "", quantity: Int64 = 1) {
        self.id = id
        self.policyID = policyID
        self.assetNameHex = assetNameHex
        self.quantity = quantity
    }
}

/// The datum an output carries.
public enum DatumDraft: Codable, Sendable, Equatable {
    case none
    /// A datum hash (hex), with the datum supplied elsewhere.
    case hash(String)
    /// Plutus data, as CBOR hex, inline in the output.
    case inline(String)
}

/// A script, as the recipe gives it.
public enum ScriptDraft: Codable, Sendable, Equatable {
    /// A native script as cardano-cli simple-script JSON.
    case native(json: String)
    /// A Plutus script (version 1–3) as CBOR hex, as in a `.plutus` file's
    /// `cborHex` or a blueprint's `compiledCode`.
    case plutus(version: Int, cborHex: String)
    /// A reference script carried by the UTxO `<transaction id>#<index>`.
    case reference(input: String)
}

/// Assets minted or burned under one policy.
public struct MintDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var script: ScriptDraft
    /// Asset names (hex) and quantities; the policy id comes from the script.
    public var assets: [AssetDraft]
    /// The redeemer, as Plutus data CBOR hex; Plutus policies only.
    public var redeemer: String
    /// The redeemer's blueprint form, when it is filled in through one.
    public var redeemerForm: BlueprintForm?
    /// The parameters the script was made with, when it is a blueprint validator that takes them.
    public var scriptParameters: BlueprintParameters?

    public init(
        id: UUID = UUID(), script: ScriptDraft = .native(json: ""), assets: [AssetDraft] = [], redeemer: String = "",
        redeemerForm: BlueprintForm? = nil, scriptParameters: BlueprintParameters? = nil
    ) {
        self.id = id
        self.script = script
        self.assets = assets
        self.redeemer = redeemer
        self.redeemerForm = redeemerForm
        self.scriptParameters = scriptParameters
    }
}

/// A script-locked UTxO to spend.
public struct ScriptInputDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// The UTxO, `<transaction id>#<index>`.
    public var input: String
    /// The script that locks it; `nil` when a reference input carries it.
    public var script: ScriptDraft?
    /// The datum, as Plutus data CBOR hex, when the UTxO holds only its hash.
    public var datum: String
    /// The redeemer, as Plutus data CBOR hex.
    public var redeemer: String
    /// The datum's and redeemer's blueprint forms, when filled in through one.
    public var datumForm: BlueprintForm?
    public var redeemerForm: BlueprintForm?
    /// The parameters the script was made with, when it is a blueprint validator that takes them.
    public var scriptParameters: BlueprintParameters?

    public init(
        id: UUID = UUID(), input: String = "", script: ScriptDraft? = nil, datum: String = "", redeemer: String = "",
        datumForm: BlueprintForm? = nil, redeemerForm: BlueprintForm? = nil, scriptParameters: BlueprintParameters? = nil
    ) {
        self.id = id
        self.input = input
        self.script = script
        self.datum = datum
        self.redeemer = redeemer
        self.datumForm = datumForm
        self.redeemerForm = redeemerForm
        self.scriptParameters = scriptParameters
    }
}

/// A certificate to include, with an identity for editing.
public struct CertificateItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var certificate: CertificateDraft

    public init(id: UUID = UUID(), certificate: CertificateDraft) {
        self.id = id
        self.certificate = certificate
    }
}

/// Every certificate the Conway ledger accepts. Genesis key delegation and
/// instantaneous rewards were removed in Conway and are not offered. Stake
/// credentials come from a stake address; DRep and committee credentials are
/// key hashes (hex); pools are `pool1…` ids.
public enum CertificateDraft: Codable, Sendable, Equatable {
    /// Register a stake address, paying the deposit (Conway, deposit stated).
    case registerStake(stakeAddress: String)
    /// Deregister a stake address, taking the deposit back (Conway).
    case deregisterStake(stakeAddress: String)
    /// Register a stake address, the pre-Conway way: the deposit is implied.
    case registerStakeLegacy(stakeAddress: String)
    /// Deregister a stake address, the pre-Conway way.
    case deregisterStakeLegacy(stakeAddress: String)
    /// Delegate stake to a pool (`pool1…` or hex).
    case delegateStake(stakeAddress: String, pool: String)
    /// Delegate votes to a DRep: `drep1…`, a key hash, `abstain` or
    /// `no-confidence`.
    case delegateVote(stakeAddress: String, drep: String)
    /// Delegate stake to a pool and votes to a DRep, in one certificate.
    case delegateStakeAndVote(stakeAddress: String, pool: String, drep: String)
    /// Register a stake address and delegate its stake, paying the deposit.
    case registerAndDelegateStake(stakeAddress: String, pool: String)
    /// Register a stake address and delegate its votes, paying the deposit.
    case registerAndDelegateVote(stakeAddress: String, drep: String)
    /// Register a stake address and delegate both, paying the deposit.
    case registerAndDelegateStakeAndVote(stakeAddress: String, pool: String, drep: String)
    /// Register a stake pool, or update one already registered.
    case registerPool(PoolRegistrationDraft)
    /// Retire a stake pool at the start of `epoch`.
    case retirePool(pool: String, epoch: UInt64?)
    case registerDRep(keyHash: String, anchorURL: String, anchorHash: String)
    case unregisterDRep(keyHash: String)
    case updateDRep(keyHash: String, anchorURL: String, anchorHash: String)
    /// Authorize a constitutional committee member's hot key.
    case authorizeCommitteeHot(coldKey: String, hotKey: String)
    /// A constitutional committee member resigns.
    case resignCommitteeCold(coldKey: String, anchorURL: String, anchorHash: String)
}

/// A stake pool's registration parameters, as the form gives them.
public struct PoolRegistrationDraft: Codable, Sendable, Equatable {
    /// The pool: `pool1…`, hex, or its cold key.
    public var pool: String
    /// The VRF key hash, or the VRF key it comes from.
    public var vrfKey: String
    /// Lovelace the owners pledge.
    public var pledge: UInt64?
    /// The fixed cost per epoch, in lovelace.
    public var cost: UInt64?
    /// The margin, as a decimal (`0.05`), a percentage (`5%`) or a fraction (`1/20`).
    public var margin: String
    /// The stake address rewards are paid to.
    public var rewardAccount: String
    /// The owners: stake addresses, stake key hashes or stake keys.
    public var owners: [String]
    public var relays: [RelayDraft]
    public var metadataURL: String
    /// Blake2b-256 of the metadata file, in hex.
    public var metadataHash: String
    /// Whether the pool is registered already, so this updates it and pays
    /// no deposit.
    public var isUpdate: Bool

    public init(
        pool: String = "", vrfKey: String = "", pledge: UInt64? = nil, cost: UInt64? = nil, margin: String = "",
        rewardAccount: String = "", owners: [String] = [], relays: [RelayDraft] = [], metadataURL: String = "",
        metadataHash: String = "", isUpdate: Bool = false
    ) {
        self.pool = pool
        self.vrfKey = vrfKey
        self.pledge = pledge
        self.cost = cost
        self.margin = margin
        self.rewardAccount = rewardAccount
        self.owners = owners
        self.relays = relays
        self.metadataURL = metadataURL
        self.metadataHash = metadataHash
        self.isUpdate = isUpdate
    }
}

/// One way to reach a pool's relay.
public struct RelayDraft: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// An IPv4 address and port.
        case ipv4
        /// An IPv6 address and port.
        case ipv6
        /// A DNS name (an A or AAAA record) and port.
        case dnsName
        /// A DNS SRV name; the port comes from the record.
        case srvName
    }

    public var id: UUID
    public var kind: Kind
    public var host: String
    public var port: UInt16?

    public init(id: UUID = UUID(), kind: Kind = .dnsName, host: String = "", port: UInt16? = 3001) {
        self.id = id
        self.kind = kind
        self.host = host
        self.port = port
    }
}

/// Rewards to withdraw from a stake address.
public struct WithdrawalDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var stakeAddress: String
    /// The whole reward balance: the ledger takes nothing less.
    public var lovelace: UInt64

    public init(id: UUID = UUID(), stakeAddress: String = "", lovelace: UInt64 = 0) {
        self.id = id
        self.stakeAddress = stakeAddress
        self.lovelace = lovelace
    }
}

/// A vote on a governance action.
public struct VoteDraft: Codable, Sendable, Equatable, Identifiable {
    public enum Voter: String, Codable, Sendable, CaseIterable {
        case drep, stakePool, committee
    }

    public enum Choice: String, Codable, Sendable, CaseIterable {
        case yes, no, abstain
    }

    public var id: UUID
    public var voter: Voter
    /// The voter's key hash (hex), or a `pool1…` id for a stake pool.
    public var voterID: String
    /// The action, `<transaction id>#<index>`.
    public var action: String
    public var choice: Choice
    public var anchorURL: String
    public var anchorHash: String

    public init(
        id: UUID = UUID(), voter: Voter = .drep, voterID: String = "", action: String = "", choice: Choice = .yes,
        anchorURL: String = "", anchorHash: String = ""
    ) {
        self.id = id
        self.voter = voter
        self.voterID = voterID
        self.action = action
        self.choice = choice
        self.anchorURL = anchorURL
        self.anchorHash = anchorHash
    }
}

/// A governance action to propose.
public struct ProposalDraft: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: Codable, Sendable, Equatable {
        case info
        /// Pay `lovelace` from the treasury to a stake address.
        case treasuryWithdrawal(stakeAddress: String, lovelace: UInt64)
    }

    public var id: UUID
    public var kind: Kind
    /// Where the deposit returns, a stake address.
    public var returnAddress: String
    public var anchorURL: String
    public var anchorHash: String

    public init(id: UUID = UUID(), kind: Kind = .info, returnAddress: String = "", anchorURL: String = "", anchorHash: String = "") {
        self.id = id
        self.kind = kind
        self.returnAddress = returnAddress
        self.anchorURL = anchorURL
        self.anchorHash = anchorHash
    }
}
