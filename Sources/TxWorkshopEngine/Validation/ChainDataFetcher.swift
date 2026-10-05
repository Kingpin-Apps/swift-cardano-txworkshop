import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import SwiftCardanoTxValidator
import TxWorkshopCore

/// Fetches everything validating a transaction needs from a provider, as a
/// snapshot the document keeps: the UTxOs its inputs point at, which are
/// spent, the protocol parameters, the tip, and the ledger state its
/// certificates, withdrawals and votes are checked against.
public struct ChainDataFetcher: Sendable {
    public typealias ContextMaker = TransactionFetcher.ContextMaker

    private let makeContext: ContextMaker

    public init(makeContext: @escaping ContextMaker = { try await ChainContextFactory().makeContext(for: $0, apiKey: $1) }) {
        self.makeContext = makeContext
    }

    /// A snapshot for `transaction`, keeping `previous`'s token names.
    public func fetch(
        transaction bytes: Data, provider: ProviderConfiguration, apiKey: String?, keeping previous: ChainContextSnapshot?
    ) async throws -> ChainContextSnapshot {
        let transaction: Transaction
        do {
            transaction = try Transaction.fromCBOR(data: bytes)
        } catch {
            throw InspectionError.malformed(String(describing: error))
        }
        let chain = try await makeContext(provider, apiKey)
        let context = try await ValidationContext.from(transaction: transaction, chainContext: chain)
        let parameters = try await chain.protocolParameters()
        return ChainContextSnapshot(
            fetchedAt: .now,
            utxos: try context.resolvedInputs.map { try $0.toCBORData().hex },
            spentInputs: context.spentInputRefs.map(InputResolver.id),
            tokens: previous?.tokens,
            protocolParameters: try JSONEncoder().encode(parameters),
            tipSlot: context.currentSlot,
            ledgerState: try LedgerState(context).encoded()
        )
    }

    /// A snapshot of the chain alone, for a document with no transaction yet:
    /// the protocol parameters, the tip, the epoch and the era. `previous`
    /// keeps its UTxOs and ledger state.
    public func fetchChain(provider: ProviderConfiguration, apiKey: String?, keeping previous: ChainContextSnapshot?) async throws -> ChainContextSnapshot {
        let chain = try await makeContext(provider, apiKey)
        let parameters = try await chain.protocolParameters()
        let slot = try? await chain.lastBlockSlot()
        var ledger = LedgerState.decode(previous?.ledgerState)
        if let epoch = try? await chain.epoch() { ledger.currentEpoch = UInt64(epoch) }
        if let era = try? await chain.era() { ledger.era = era.rawValue }
        return ChainContextSnapshot(
            fetchedAt: .now,
            utxos: previous?.utxos ?? [],
            spentInputs: previous?.spentInputs,
            tokens: previous?.tokens,
            protocolParameters: try JSONEncoder().encode(parameters),
            tipSlot: slot.map(UInt64.init),
            ledgerState: try ledger.encoded()
        )
    }
}
