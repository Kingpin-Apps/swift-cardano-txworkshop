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
}
