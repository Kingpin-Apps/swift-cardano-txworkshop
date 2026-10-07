import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import SwiftCardanoTxBuilder
import TxWorkshopCore

/// Makes a transaction hardware wallets can sign (CIP-21) by building it
/// again, for hardware wallets.
///
/// Writing a body the way CIP-21 asks can change its length: sets gain a
/// tag, collections and lengths are written differently. The fee is charged
/// on those bytes, and the body is what is signed, so rewriting the bytes of
/// a built transaction would leave a fee sized for other bytes. Building
/// again sizes the fee from the bytes that will be signed, and the change
/// pays the difference.
///
/// - With the document's build form, the form is built again with
///   ``BuildRecipe/cip21Compatible`` on, spending the inputs the
///   transaction spends.
/// - Without it, the transaction itself is built again: the same inputs and
///   outputs, certificates, withdrawals, mint, native scripts, metadata and
///   validity, with the change worked out anew. A transaction that runs
///   Plutus scripts, votes, proposes or uses reference inputs needs its build
///   form for that.
public enum CIP21Rebuild {
    public enum Source: String, Sendable, Equatable {
        case recipe, transaction
    }

    public struct Result: Sendable, Equatable {
        /// The rebuilt transaction, unsigned.
        public let transaction: Data
        public let id: String
        public let source: Source
        public let previousFee: UInt64
        public let fee: UInt64
        /// Signatures the old transaction carried: they signed its id, which
        /// has changed.
        public let droppedSignatures: Int
        /// The build form to keep: the document's, now building for hardware
        /// wallets. Nil when the transaction itself was rebuilt.
        public let recipe: BuildRecipe?
        /// What CIP-21 says of the rebuilt transaction.
        public let report: CIP21Report
    }

    @concurrent
    public static func rebuild(
        _ bytes: Data, recipe: BuildRecipe?, snapshot: ChainContextSnapshot?, network: CardanoNetwork?,
        provider: ProviderConfiguration? = nil, apiKey: String? = nil
    ) async throws -> Result {
        let old = try TransactionValidation.decode(bytes)
        let dropped = old.transactionWitnessSet.vkeyWitnesses?.count ?? 0
        let rebuilt: Data
        let source: Source
        var kept: BuildRecipe?
        if let recipe {
            var forHardware = recipe
            forHardware.cip21Compatible = true
            // The same inputs, so it is the same transaction, written anew.
            var building = forHardware
            for input in old.transactionBody.inputs.asArray.map(InputResolver.id)
            where !building.fixedInputs.contains(input) && !building.excludedInputs.contains(input) {
                building.fixedInputs.append(input)
            }
            rebuilt = try await TransactionComposer()
                .compose(building, snapshot: snapshot, network: network, provider: provider, apiKey: apiKey)
                .transaction
            source = .recipe
            kept = forHardware
        } else {
            rebuilt = try await fromTransaction(old, snapshot: snapshot, network: network)
            source = .transaction
        }
        let new = try TransactionValidation.decode(rebuilt)
        return Result(
            transaction: rebuilt, id: new.id?.payload.hex ?? "", source: source,
            previousFee: UInt64(old.transactionBody.fee), fee: UInt64(new.transactionBody.fee),
            droppedSignatures: dropped, recipe: kept, report: try CIP21Check.report(rebuilt)
        )
    }

    // MARK: - From the transaction

    /// `transaction` built again for hardware wallets, from what it holds.
    static func fromTransaction(_ transaction: Transaction, snapshot: ChainContextSnapshot?, network: CardanoNetwork?) async throws -> Data {
        guard let parameters = TransactionValidation.protocolParameters(snapshot) else {
            throw RebuildError.noProtocolParameters
        }
        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet
        var needsForm: [String] = []
        if body.scriptDataHash != nil || witnesses.redeemers != nil || body.collateral != nil {
            needsForm.append("it runs Plutus scripts")
        }
        if body.referenceInputs != nil { needsForm.append("it uses reference inputs") }
        if body.votingProcedures != nil { needsForm.append("it votes") }
        if body.proposalProcedures != nil { needsForm.append("it proposes") }
        if body.currentTreasuryAmount != nil { needsForm.append("it states the treasury amount") }
        if witnesses.bootstrapWitness != nil { needsForm.append("it spends from Byron addresses") }
        guard needsForm.isEmpty else { throw RebuildError.needsBuildForm(needsForm) }

        let known = Dictionary(
            TransactionValidation.utxos(snapshot).map { (InputResolver.id($0.input), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let inputs = body.inputs.asArray
        let missing = inputs.map(InputResolver.id).filter { known[$0] == nil }
        guard missing.isEmpty else { throw RebuildError.missingInputs(missing) }
        let spent = inputs.compactMap { known[InputResolver.id($0)] }
        guard let changeIndex = changeOutput(of: body, spending: spent) else { throw RebuildError.noChange }
        let change = body.outputs[changeIndex].address

        let context = WorkshopChainContext(
            network: network, parameters: parameters, known: spent, resolvable: [], tipSlot: snapshot?.tipSlot, live: nil
        )
        let builder = TxBuilder(context: context)
        builder.cip21Compatible = true
        for utxo in spent { builder.addInput(utxo) }
        for (index, output) in body.outputs.enumerated() where index != changeIndex {
            try builder.addOutput(output)
        }
        builder.certificates = body.certificates?.asList
        builder.withdrawals = body.withdrawals
        builder.mint = body.mint
        builder.nativeScripts = witnesses.nativeScripts?.asList
        builder.auxiliaryData = transaction.auxiliaryData
        builder.ttl = body.ttl
        builder.validityStart = body.validityStart
        builder.requiredSigners = body.requiredSigners?.asList
        if let donation = body.treasuryDonation {
            try builder.addTreasuryDonation(Int(donation.value))
        }
        // A pool registration pays the pool deposit only the first time: the
        // old transaction paid it if what it spent leaves room for it.
        if body.certificates?.asList.contains(where: { if case .poolRegistration = $0 { true } else { false } }) == true {
            builder.initialStakePoolRegistration = lovelaceLeftOver(body, spending: spent) >= parameters.stakePoolDeposit
        }

        let built: TransactionBody
        do {
            built = try await builder.build(changeAddress: change)
        } catch {
            throw RebuildError.builder(String(describing: error))
        }
        let rebuilt = Transaction(
            transactionBody: built, transactionWitnessSet: try builder.buildWitnessSet(), valid: true,
            auxiliaryData: builder.auxiliaryData
        )
        return try rebuilt.toCBORData()
    }

    /// The output the change went to: the last one paying the one address,
    /// among those the inputs come from, that any output pays.
    static func changeOutput(of body: TransactionBody, spending spent: [UTxO]) -> Int? {
        let sources = Set(spent.map(\.output.address))
        let paid = Set(body.outputs.map(\.address)).intersection(sources)
        guard paid.count == 1, let address = paid.first else { return nil }
        return body.outputs.lastIndex { $0.address == address }
    }

    /// Lovelace the inputs and withdrawals bring that the outputs, fee and
    /// donation do not take: what deposits took.
    static func lovelaceLeftOver(_ body: TransactionBody, spending spent: [UTxO]) -> Int64 {
        let inputs = spent.reduce(Int64(0)) { $0 + $1.output.amount.coin }
        let withdrawn = body.withdrawals?.data.values.reduce(Int64(0)) { $0 + Int64($1) } ?? 0
        let outputs = body.outputs.reduce(Int64(0)) { $0 + $1.amount.coin }
        let donation = body.treasuryDonation.map { Int64($0.value) } ?? 0
        return inputs + withdrawn - outputs - Int64(body.fee) - donation
    }
}

public enum RebuildError: Error, Sendable, Equatable, CustomStringConvertible {
    case noProtocolParameters
    case missingInputs([String])
    case noChange
    case needsBuildForm([String])
    case builder(String)

    public var description: String {
        switch self {
        case .noProtocolParameters:
            "Rebuilding needs the protocol parameters: fetch chain data first."
        case .missingInputs(let inputs):
            "Rebuilding needs the UTxOs the transaction spends: fetch chain data first. Missing: \(inputs.joined(separator: ", "))."
        case .noChange:
            "The fee is paid from the change, and no output is plainly the change: none, or more than one, of the addresses the inputs come from is paid. Build it in Build, for hardware wallets."
        case .needsBuildForm(let reasons):
            "This transaction is rebuilt from its build form, as \(reasons.joined(separator: ", ")). Build it in Build, for hardware wallets."
        case .builder(let message):
            message
        }
    }
}
