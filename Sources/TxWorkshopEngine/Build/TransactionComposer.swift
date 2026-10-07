import Foundation
import OrderedCollections
import SwiftCardanoChain
import SwiftCardanoCore
import SwiftCardanoTxBuilder
import TxWorkshopCore

/// Builds a transaction from a ``BuildRecipe`` with swift-cardano-txbuilder:
/// coin selection, change, min-ADA and the fee, iterated to a fixed point.
public struct TransactionComposer: Sendable {
    public init() {}

    /// A built, unsigned transaction and what went into it.
    public struct Composition: Sendable, Equatable {
        public let transaction: Data
        public let id: String
        public let fee: FeeBreakdownView
        /// The inputs coin selection spent, as `<transaction id>#<index>`.
        public let inputs: [String]
        /// Those inputs with what they hold, so they can be chosen again.
        public let spent: [SpentInput]
        public let totalIn: Int64
        public let totalOut: Int64
        /// Lovelace the change output carries, when there is one.
        public let change: Int64?
        public let deposits: Int64
        public let refunds: Int64
    }

    /// An input the transaction spends.
    public struct SpentInput: Sendable, Equatable, Identifiable {
        /// `<transaction id>#<index>`.
        public let id: String
        public let lovelace: Int64
        public let assetCount: Int

        public init(id: String, lovelace: Int64, assetCount: Int) {
            self.id = id
            self.lovelace = lovelace
            self.assetCount = assetCount
        }
    }

    /// The fee, item by item.
    public struct FeeBreakdownView: Sendable, Equatable {
        public let total: UInt64
        public let sizeBytes: UInt64
        public let sizeFee: UInt64
        public let fixedFee: UInt64
        public let memory: UInt64
        public let memoryFee: UInt64
        public let steps: UInt64
        public let stepsFee: UInt64
        public let referenceScriptBytes: UInt64
        public let referenceScriptFee: UInt64
        public let referenceScriptTiers: [Tier]
        public let buffer: UInt64

        public struct Tier: Sendable, Equatable {
            public let bytes: UInt64
            public let pricePerByte: Double
            public let fee: Double
        }
    }

    /// Builds `recipe`. Protocol parameters come from `snapshot`, else from
    /// `provider`; addresses' UTxOs from the recipe, and from `provider`
    /// when given.
    @concurrent
    public func compose(
        _ recipe: BuildRecipe, snapshot: ChainContextSnapshot?, network: CardanoNetwork?,
        provider: ProviderConfiguration? = nil, apiKey: String? = nil
    ) async throws -> Composition {
        // The recipe's values are read in any form they were given in; some
        // (a key hash for an address) need the network.
        let problems = RecipeCheck.problems(recipe, network: network)
        guard problems.isEmpty else { throw ComposeError.invalidRecipe(problems) }
        return try await ValueReader.$buildNetwork.withValue(network) {
            try await build(recipe, snapshot: snapshot, network: network, provider: provider, apiKey: apiKey)
        }
    }

    private func build(
        _ recipe: BuildRecipe, snapshot: ChainContextSnapshot?, network: CardanoNetwork?,
        provider: ProviderConfiguration?, apiKey: String?
    ) async throws -> Composition {
        let live: (any ChainContext)? = if let provider {
            try await ChainContextFactory().makeContext(for: provider, apiKey: apiKey)
        } else {
            nil
        }
        let parameters: ProtocolParameters
        if let saved = TransactionValidation.protocolParameters(snapshot) {
            parameters = saved
        } else if let live {
            parameters = try await live.protocolParameters()
        } else {
            throw ComposeError.noProtocolParameters
        }
        let context = WorkshopChainContext(
            network: network, parameters: parameters, known: try recipe.utxos.map(Self.utxo),
            resolvable: TransactionValidation.utxos(snapshot),
            tipSlot: live == nil ? snapshot?.tipSlot : nil, live: live
        )
        return try await build(recipe, context: context, parameters: parameters)
    }

    func build(_ recipe: BuildRecipe, context: WorkshopChainContext, parameters: ProtocolParameters) async throws -> Composition {
        var context = context
        context.excluded = Set(recipe.excludedInputs.map { $0.trimmingCharacters(in: .whitespaces) })
        let selectors: [UTxOSelector] = switch recipe.coinSelection {
        case .randomImprove: [RandomImproveMultiAsset(), LargestFirstSelector()]
        case .largestFirst: [LargestFirstSelector(), RandomImproveMultiAsset()]
        }
        let builder = TxBuilder(context: context, utxoSelectors: selectors)
        builder.feeBuffer = recipe.feeBuffer.map { Int($0) }
        builder.cip21Compatible = recipe.cip21Compatible
        builder.validityStart = recipe.validFrom.map { SlotNumber($0) }
        builder.ttl = recipe.validUntil.map { SlotNumber($0) }

        let sources = try recipe.sourceAddresses.filter { !$0.isEmpty }.map { try Self.address($0) }
        for address in sources { builder.addInputAddress(.address(address)) }
        // Pasted UTxOs are spendable even without their address listed.
        for address in Set(context.known.map(\.output.address)) where !sources.contains(address) {
            builder.addInputAddress(.address(address))
        }
        for id in recipe.fixedInputs {
            let reference = try ValueReader.value(.transactionInput, id) { _ in ComposeError.unknownInput(id) }
            guard let input = TransactionValidation.input(reference), let (utxo, _) = try await context.utxo(input: input) else {
                throw ComposeError.unknownInput(id)
            }
            builder.addInput(utxo)
        }
        for draft in recipe.outputs {
            try builder.addOutput(try await Self.output(draft, context: context))
        }
        if !recipe.requiredSigners.isEmpty {
            builder.requiredSigners = try recipe.requiredSigners.map { text in
                let hex = try ValueReader.value(.keyHash, text) { _ in ComposeError.badKeyHash(text) }
                guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), bytes.count == 28 else { throw ComposeError.badKeyHash(hex) }
                return VerificationKeyHash(payload: bytes)
            }
        }
        if let metadata = try Self.message(recipe.message) {
            builder.auxiliaryData = metadata
        }
        try await Self.addScripts(recipe, to: builder, context: context)
        let deposits = try Self.addGovernance(recipe, to: builder, parameters: parameters)

        let change = try recipe.changeAddress.isEmpty ? sources.first : Self.address(recipe.changeAddress)
        guard let change else { throw ComposeError.noChangeAddress }
        let body: TransactionBody
        do {
            body = try await builder.build(changeAddress: change)
        } catch let error as ComposeError {
            throw error
        } catch {
            throw ComposeError.builder(String(describing: error))
        }
        let witnesses = try builder.buildWitnessSet()
        let transaction = Transaction(
            transactionBody: body, transactionWitnessSet: witnesses, valid: true, auxiliaryData: builder.auxiliaryData
        )
        let bytes = try transaction.toCBORData()
        let breakdown = try await builder.estimateFeeBreakdown()

        let inputs = body.inputs.asArray
        var totalIn: Int64 = 0
        var spent: [SpentInput] = []
        for input in inputs {
            guard let (utxo, _) = try await context.utxo(input: input) else { continue }
            totalIn += utxo.output.amount.coin
            spent.append(SpentInput(id: InputResolver.id(input), lovelace: utxo.output.amount.coin, assetCount: Self.assetCount(utxo)))
        }
        let totalOut = body.outputs.reduce(Int64(0)) { $0 + $1.amount.coin }
        // The builder adds change after the outputs asked for.
        let changeOutput = body.outputs.count > recipe.outputs.count ? body.outputs.last : nil
        return Composition(
            transaction: bytes,
            id: transaction.id?.payload.hex ?? "",
            fee: Self.view(breakdown),
            inputs: inputs.map(InputResolver.id),
            spent: spent,
            totalIn: totalIn,
            totalOut: totalOut,
            change: changeOutput?.amount.coin,
            deposits: deposits.paid,
            refunds: deposits.refunded
        )
    }

    static func view(_ breakdown: FeeBreakdown) -> FeeBreakdownView {
        FeeBreakdownView(
            total: breakdown.total, sizeBytes: breakdown.sizeBytes, sizeFee: breakdown.sizeFee, fixedFee: breakdown.fixedFee,
            memory: breakdown.memory, memoryFee: breakdown.memoryFee, steps: breakdown.steps, stepsFee: breakdown.stepsFee,
            referenceScriptBytes: breakdown.referenceScriptBytes, referenceScriptFee: breakdown.referenceScriptFee,
            referenceScriptTiers: breakdown.referenceScriptTiers.map { .init(bytes: $0.bytes, pricePerByte: $0.pricePerByte, fee: $0.fee) },
            buffer: breakdown.buffer
        )
    }

    // MARK: Drafts to ledger values

    static func address(_ text: String) throws -> Address {
        let value = try ValueReader.value(.address, text) { _ in ComposeError.badAddress(text) }
        do {
            return try Address(from: .string(value))
        } catch {
            throw ComposeError.badAddress(text)
        }
    }

    static func utxo(_ hex: String) throws -> UTxO {
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), let utxo = try? UTxO.fromCBOR(data: bytes) else {
            throw ComposeError.badUTxO(String(hex.prefix(24)))
        }
        return utxo
    }

    static func output(_ draft: OutputDraft, context: WorkshopChainContext) async throws -> TransactionOutput {
        let multiAsset = try Self.multiAsset(draft.assets.map { ($0.policyID, $0.assetNameHex, $0.quantity) })
        var output = TransactionOutput(
            address: try address(draft.address),
            amount: Value(coin: Int64(draft.lovelace ?? 0), multiAsset: multiAsset),
            postAlonzo: true
        )
        switch draft.datum {
        case .none:
            break
        case .hash(let hex):
            guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), bytes.count == 32 else { throw ComposeError.badDatum }
            output.datumOption = DatumOption(datum: .datumHash(DatumHash(payload: bytes)))
        case .inline(let text):
            let hex = try ValueReader.value(.plutusData, text) { _ in ComposeError.badDatum }
            guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), let data = try? PlutusData.fromCBOR(data: bytes) else {
                throw ComposeError.badDatum
            }
            output.datumOption = DatumOption(datum: .data(data))
        }
        let least = Int64(try await Utils.minLovelacePostAlonzo(output, context))
        if draft.lovelace == nil {
            output.amount.coin = least
            // The coin's own size can raise the minimum.
            output.amount.coin = Int64(try await Utils.minLovelacePostAlonzo(output, context))
        } else if output.amount.coin < least {
            throw ComposeError.belowMinimum(address: draft.address, minimum: least)
        }
        return output
    }

    /// Assets from policy ids and asset names in hex. Built from bytes: the
    /// string form of `MultiAsset(from:)` reads names as UTF-8 text.
    static func multiAsset(_ assets: [(policy: String, nameHex: String, quantity: Int64)]) throws -> MultiAsset {
        var policies: [ScriptHash: OrderedDictionary<AssetName, Int64>] = [:]
        for (policy, nameHex, quantity) in assets where quantity != 0 {
            let policyHex = try ValueReader.value(.policyID, policy) { ComposeError.badAsset("\(policy): \($0)") }
            guard let policyBytes = try? TxDocumentCodec.bytes(fromHex: policyHex), policyBytes.count == 28 else {
                throw ComposeError.badAsset("\(policy) is not a 28-byte policy id.")
            }
            let nameValue = nameHex.isEmpty ? "" : try ValueReader.value(.assetName, nameHex) { ComposeError.badAsset("\(nameHex): \($0)") }
            let nameBytes = nameValue.isEmpty ? Data() : (try? TxDocumentCodec.bytes(fromHex: nameValue))
            guard let nameBytes, nameBytes.count <= 32, let name = try? AssetName(payload: nameBytes) else {
                throw ComposeError.badAsset("\(nameHex) is not an asset name of up to 32 bytes in hex.")
            }
            policies[ScriptHash(payload: policyBytes), default: [:]][name, default: 0] += quantity
        }
        return MultiAsset(policies.mapValues { Asset($0) })
    }

    /// Label 674 metadata: `{"msg": [line, …]}`, lines split at 64 bytes.
    static func message(_ text: String) throws -> AuxiliaryData? {
        let lines = text.split(separator: "\n").filter { !$0.allSatisfy(\.isWhitespace) }.flatMap { line -> [String] in
            var chunks: [String] = []
            var current = ""
            for character in line {
                if (current + String(character)).utf8.count > 64 {
                    chunks.append(current)
                    current = ""
                }
                current.append(character)
            }
            if !current.isEmpty { chunks.append(current) }
            return chunks
        }
        guard !lines.isEmpty else { return nil }
        let message = TransactionMetadatum.map([.text("msg"): .list(lines.map { .text($0) })])
        return AuxiliaryData(data: .metadata(try Metadata([674: message])))
    }
}

public enum ComposeError: Error, Sendable, Equatable, CustomStringConvertible {
    case noProtocolParameters
    case noChangeAddress
    case badAddress(String)
    case badUTxO(String)
    case badAsset(String)
    case badDatum
    case badKeyHash(String)
    case badScript(String)
    case badPlutusData(String)
    case badGovernance(String)
    case unknownInput(String)
    case belowMinimum(address: String, minimum: Int64)
    case scriptFails(String, String)
    case builder(String)
    /// The recipe has mistakes, each named where it is.
    case invalidRecipe([RecipeProblem])

    public var description: String {
        switch self {
        case .invalidRecipe(let problems):
            (["Fix these first:"] + problems.map { "• \($0)" }).joined(separator: "\n")
        case .noProtocolParameters: "Building needs protocol parameters: fetch chain data, enter them by hand, or pick a provider."
        case .noChangeAddress: "Add a source address or a change address."
        case .badAddress(let text): "\"\(text)\" is not an address."
        case .badUTxO(let start): "The UTxO starting \(start)… is not UTxO CBOR."
        case .badAsset(let reason): "An asset is not valid: \(reason)"
        case .badDatum: "A datum is not a 32-byte hash or Plutus data in CBOR hex."
        case .badKeyHash(let hex): "\(hex) is not a 28-byte key hash."
        case .badScript(let reason): reason
        case .badGovernance(let reason): reason
        case .badPlutusData(let what): "\(what.prefix(1).uppercased() + what.dropFirst()) is not Plutus data in CBOR hex."
        case .unknownInput(let id): "\(id) is not among the UTxOs the builder knows."
        case .belowMinimum(let address, let minimum): "The output to \(address) needs at least \(minimum) lovelace."
        case .scriptFails(let redeemer, let reason): "The \(redeemer) script fails: \(reason)"
        case .builder(let reason): reason
        }
    }
}

extension TransactionComposer {
    /// The UTxOs at `addresses`, from `provider`, as CBOR hex: for a recipe
    /// to keep, so it builds offline later.
    @concurrent
    public func utxos(at addresses: [String], provider: ProviderConfiguration, apiKey: String?) async throws -> [String] {
        let chain = try await ChainContextFactory().makeContext(for: provider, apiKey: apiKey)
        var found: [String] = []
        for text in addresses where !text.trimmingCharacters(in: .whitespaces).isEmpty {
            for utxo in try await chain.utxos(address: try Self.address(text)) {
                found.append(try utxo.toCBORData().hex)
            }
        }
        return found
    }

    /// A UTxO's reference and lovelace, for listing pasted UTxOs.
    public static func describe(utxoHex: String) -> (id: String, lovelace: Int64, assetCount: Int)? {
        guard let utxo = try? utxo(utxoHex) else { return nil }
        return (InputResolver.id(utxo.input), utxo.output.amount.coin, assetCount(utxo))
    }

    static func assetCount(_ utxo: UTxO) -> Int {
        utxo.output.amount.multiAsset.data.values.reduce(0) { $0 + $1.data.count }
    }
}
