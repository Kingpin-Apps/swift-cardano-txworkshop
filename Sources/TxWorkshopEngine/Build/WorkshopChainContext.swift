import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import SwiftCardanoUPLC
import TxWorkshopCore

/// The chain as the builder sees it: the document's saved protocol parameters
/// and tip, UTxOs pasted or saved, scripts evaluated locally, and anything
/// else from a live provider when there is one. With no provider, building
/// works offline.
struct WorkshopChainContext: ChainContext {
    let network: CardanoNetwork?
    let parameters: ProtocolParameters
    /// UTxOs the builder may spend, beyond what the live provider finds.
    let known: [UTxO]
    /// UTxOs it may only look up, such as the document's saved chain data:
    /// the outputs of reference inputs, or of inputs the recipe names.
    var resolvable: [UTxO] = []
    let tipSlot: UInt64?
    let live: (any ChainContext)?

    var name: String { "Tx Workshop" }
    var type: ContextType { live == nil ? .offline : .online }
    var networkId: NetworkId { network == .mainnet ? .mainnet : .testnet }

    func protocolParameters() async throws -> ProtocolParameters { parameters }

    func genesisParameters() async throws -> GenesisParameters {
        guard let live else { throw CardanoChainError.notImplemented("Genesis parameters need a provider.") }
        return try await live.genesisParameters()
    }

    func epoch() async throws -> Int { try await live?.epoch() ?? 0 }
    func era() async throws -> Era? { try await live?.era() ?? .conway }

    func lastBlockSlot() async throws -> Int {
        if let tipSlot { return Int(tipSlot) }
        guard let live else { throw CardanoChainError.notImplemented("The tip slot needs a provider, or set validity by hand.") }
        return try await live.lastBlockSlot()
    }

    func utxos(address: Address) async throws -> [UTxO] {
        var found = known.filter { $0.output.address == address }
        if let live {
            let ids = Set(found.map { InputResolver.id($0.input) })
            found += try await live.utxos(address: address).filter { !ids.contains(InputResolver.id($0.input)) }
        }
        return found
    }

    func utxo(input: TransactionInput) async throws -> (UTxO, isSpent: Bool)? {
        if let utxo = (known + resolvable).first(where: { $0.input == input }) { return (utxo, false) }
        return try await live?.utxo(input: input)
    }

    /// Runs every script locally with the saved cost models, keyed the way
    /// providers key them: `<tag>:<index>`.
    func evaluateTx(tx: Transaction) async throws -> [String: ExecutionUnits] {
        var resolved = known + resolvable
        for input in tx.transactionBody.inputs.asArray + (tx.transactionBody.referenceInputs?.asList ?? [])
        where !resolved.contains(where: { $0.input == input }) {
            if let (utxo, _) = try await utxo(input: input) { resolved.append(utxo) }
        }
        let phaseTwo = try PhaseTwo(protocolParameters: parameters, slotTimeline: PhaseTwoRun.timeline(network))
        let result = try await phaseTwo.evaluate(transaction: tx, resolvedInputs: resolved)
        let redeemers = PhaseTwo.redeemers(of: tx)
        var units: [String: ExecutionUnits] = [:]
        for run in result.redeemers {
            guard redeemers.indices.contains(run.index), let tag = redeemers[run.index].tag else { continue }
            guard run.passed, let consumed = run.consumedBudget else {
                throw ComposeError.scriptFails("\(tag.description()) \(redeemers[run.index].index)", run.error.map { "\($0)" } ?? "")
            }
            units["\(tag.description()):\(redeemers[run.index].index)"] = ExecutionUnits(mem: consumed.mem, steps: consumed.cpu)
        }
        return units
    }
}
