import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import TxWorkshopCore

/// A transaction found on chain, and the network it was found on.
public struct FetchedTransaction: Sendable, Equatable {
    public let cbor: Data
    public let network: CardanoNetwork
}

public enum FetchError: Error, Sendable, Equatable, CustomStringConvertible {
    case notAHash
    case noProviders
    /// No network's provider had it; the reason from each, by network.
    case notFound([String])

    public var description: String {
        switch self {
        case .notAHash: "A transaction id is 64 hexadecimal characters."
        case .noProviders: "Add a Blockfrost or Koios provider to look transactions up."
        case .notFound(let reasons): "Not found on any network. \(reasons.joined(separator: " "))"
        }
    }
}

/// Looks a transaction up by id on every configured network at once.
public struct TransactionFetcher: Sendable {
    /// A provider to ask, with its API key.
    public struct Source: Sendable {
        public let provider: ProviderConfiguration
        public let apiKey: String?

        public init(provider: ProviderConfiguration, apiKey: String?) {
            self.provider = provider
            self.apiKey = apiKey
        }
    }

    public typealias ContextMaker = @Sendable (ProviderConfiguration, String?) async throws -> any ChainContext

    private let makeContext: ContextMaker

    public init(makeContext: @escaping ContextMaker = { try await ChainContextFactory().makeContext(for: $0, apiKey: $1) }) {
        self.makeContext = makeContext
    }

    /// The transaction with id `hash`, from whichever source has it first.
    /// Only Blockfrost and Koios can look transactions up; other sources are
    /// skipped.
    public func fetch(hash: String, from sources: [Source]) async throws -> FetchedTransaction {
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 64, let id = try? TransactionId(from: .string(trimmed)) else {
            throw FetchError.notAHash
        }
        let usable = sources.filter { $0.provider.kind == .blockfrost || $0.provider.kind == .koios }
        guard !usable.isEmpty else { throw FetchError.noProviders }

        return try await withThrowingTaskGroup(of: Result<FetchedTransaction, FetchFailure>.self) { group in
            for source in usable {
                group.addTask {
                    do {
                        let context = try await makeContext(source.provider, source.apiKey)
                        let transaction = try await context.transaction(hash: id)
                        return .success(FetchedTransaction(cbor: try transaction.toCBORData(), network: source.provider.network))
                    } catch {
                        return .failure(FetchFailure(network: source.provider.network, reason: String(describing: error)))
                    }
                }
            }
            var failures: [String] = []
            for try await result in group {
                switch result {
                case .success(let fetched):
                    group.cancelAll()
                    return fetched
                case .failure(let failure):
                    failures.append("\(failure.network.id): \(failure.reason)")
                }
            }
            throw FetchError.notFound(failures.sorted())
        }
    }

    struct FetchFailure: Error {
        let network: CardanoNetwork
        let reason: String
    }
}
