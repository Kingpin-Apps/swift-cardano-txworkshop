import Foundation
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
        public let totalIn: Int64
        public let totalOut: Int64
        /// Lovelace the change output carries, when there is one.
        public let change: Int64?
        public let deposits: Int64
        public let refunds: Int64
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
        let selectors: [UTxOSelector] = switch recipe.coinSelection {
        case .randomImprove: [RandomImproveMultiAsset(), LargestFirstSelector()]
        case .largestFirst: [LargestFirstSelector(), RandomImproveMultiAsset()]
        }
        let builder = TxBuilder(context: context, utxoSelectors: selectors)
        builder.feeBuffer = recipe.feeBuffer.map { Int($0) }
        builder.validityStart = recipe.validFrom.map { SlotNumber($0) }
        builder.ttl = recipe.validUntil.map { SlotNumber($0) }

        let sources = try recipe.sourceAddresses.filter { !$0.isEmpty }.map { try Self.address($0) }
        for address in sources { builder.addInputAddress(.address(address)) }
        // Pasted UTxOs are spendable even without their address listed.
        for address in Set(context.known.map(\.output.address)) where !sources.contains(address) {
            builder.addInputAddress(.address(address))
        }
        for id in recipe.fixedInputs {
            guard let input = TransactionValidation.input(id), let (utxo, _) = try await context.utxo(input: input) else {
                throw ComposeError.unknownInput(id)
            }
            builder.addInput(utxo)
        }
        for draft in recipe.outputs {
            try builder.addOutput(try await Self.output(draft, context: context))
        }
        if !recipe.requiredSigners.isEmpty {
            builder.requiredSigners = try recipe.requiredSigners.map { hex in
                guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), bytes.count == 28 else { throw ComposeError.badKeyHash(hex) }
                return VerificationKeyHash(payload: bytes)
            }
        }
        if let metadata = try Self.message(recipe.message) {
            builder.auxiliaryData = metadata
        }

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
        for input in inputs {
            if let (utxo, _) = try await context.utxo(input: input) { totalIn += utxo.output.amount.coin }
        }
        let totalOut = body.outputs.reduce(Int64(0)) { $0 + $1.amount.coin }
        // The builder adds change after the outputs asked for.
        let changeOutput = body.outputs.count > recipe.outputs.count ? body.outputs.last : nil
        return Composition(
            transaction: bytes,
            id: transaction.id?.payload.hex ?? "",
            fee: Self.view(breakdown),
            inputs: inputs.map(InputResolver.id),
            totalIn: totalIn,
            totalOut: totalOut,
            change: changeOutput?.amount.coin,
            deposits: 0,
            refunds: 0
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
        do {
            return try Address(from: .string(text.trimmingCharacters(in: .whitespacesAndNewlines)))
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
        var assets: [String: [String: Int64]] = [:]
        for asset in draft.assets where asset.quantity != 0 {
            assets[asset.policyID, default: [:]][asset.assetNameHex, default: 0] += asset.quantity
        }
        let multiAsset: MultiAsset
        do {
            multiAsset = assets.isEmpty ? MultiAsset([:]) : try MultiAsset(from: assets.mapValues { $0.mapKeys { "0x" + $0 } })
        } catch {
            throw ComposeError.badAsset(String(describing: error))
        }
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
        case .inline(let hex):
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
    case unknownInput(String)
    case belowMinimum(address: String, minimum: Int64)
    case scriptFails(String, String)
    case builder(String)

    public var description: String {
        switch self {
        case .noProtocolParameters: "Building needs protocol parameters: fetch chain data, enter them by hand, or pick a provider."
        case .noChangeAddress: "Add a source address or a change address."
        case .badAddress(let text): "\"\(text)\" is not an address."
        case .badUTxO(let start): "The UTxO starting \(start)… is not UTxO CBOR."
        case .badAsset(let reason): "An asset is not valid: \(reason)"
        case .badDatum: "A datum is not a 32-byte hash or Plutus data in CBOR hex."
        case .badKeyHash(let hex): "\(hex) is not a 28-byte key hash."
        case .unknownInput(let id): "\(id) is not among the UTxOs the builder knows."
        case .belowMinimum(let address, let minimum): "The output to \(address) needs at least \(minimum) lovelace."
        case .scriptFails(let redeemer, let reason): "The \(redeemer) script fails: \(reason)"
        case .builder(let reason): reason
        }
    }
}

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
