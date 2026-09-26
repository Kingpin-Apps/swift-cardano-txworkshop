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

    public enum CoinSelection: String, Codable, Sendable, CaseIterable {
        case randomImprove, largestFirst
    }

    public init(
        sourceAddresses: [String] = [], utxos: [String] = [], fixedInputs: [String] = [], outputs: [OutputDraft] = [],
        changeAddress: String = "", coinSelection: CoinSelection = .randomImprove, validFrom: UInt64? = nil,
        validUntil: UInt64? = nil, message: String = "", requiredSigners: [String] = [], feeBuffer: UInt64? = nil,
        mints: [MintDraft] = [], scriptInputs: [ScriptInputDraft] = [], collateral: [String] = []
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

    public init(
        id: UUID = UUID(), address: String = "", lovelace: UInt64? = nil, assets: [AssetDraft] = [],
        datum: DatumDraft = .none, referenceScript: String? = nil
    ) {
        self.id = id
        self.address = address
        self.lovelace = lovelace
        self.assets = assets
        self.datum = datum
        self.referenceScript = referenceScript
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

    public init(id: UUID = UUID(), script: ScriptDraft = .native(json: ""), assets: [AssetDraft] = [], redeemer: String = "") {
        self.id = id
        self.script = script
        self.assets = assets
        self.redeemer = redeemer
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

    public init(id: UUID = UUID(), input: String = "", script: ScriptDraft? = nil, datum: String = "", redeemer: String = "") {
        self.id = id
        self.input = input
        self.script = script
        self.datum = datum
        self.redeemer = redeemer
    }
}
