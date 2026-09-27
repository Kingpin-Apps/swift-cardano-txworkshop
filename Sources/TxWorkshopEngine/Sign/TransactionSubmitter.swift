import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import TxWorkshopCore

/// Submits a signed transaction through a provider, and asks whether it is
/// on chain yet.
public struct TransactionSubmitter: Sendable {
    public typealias ContextMaker = TransactionFetcher.ContextMaker

    private let makeContext: ContextMaker

    public init(makeContext: @escaping ContextMaker = { try await ChainContextFactory().makeContext(for: $0, apiKey: $1) }) {
        self.makeContext = makeContext
    }

    /// Submits `bytes` exactly as they are, returning the transaction id the
    /// provider reports.
    public func submit(_ bytes: Data, provider: ProviderConfiguration, apiKey: String?) async throws -> String {
        let chain = try await makeContext(provider, apiKey)
        do {
            return try await chain.submitTxCBOR(cbor: bytes).trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
        } catch {
            throw SubmitError.refused(String(describing: error))
        }
    }

    /// Whether transaction `id` is on chain: its first output exists (spent
    /// or not), or the provider can look the transaction up.
    public func isOnChain(_ id: String, provider: ProviderConfiguration, apiKey: String?) async throws -> Bool {
        guard let input = TransactionValidation.input("\(id)#0") else { throw SubmitError.badID(id) }
        let chain = try await makeContext(provider, apiKey)
        if let found = try? await chain.utxo(input: input), found != nil { return true }
        return (try? await chain.transactionCBOR(hash: input.transactionId)) != nil
    }
}

public enum SubmitError: Error, Sendable, Equatable, CustomStringConvertible {
    case refused(String)
    case badID(String)

    public var description: String {
        switch self {
        case .refused(let reason): "The provider refused it: \(reason)"
        case .badID(let id): "\(id) is not a transaction id."
        }
    }
}
