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
        case .notAHash: "Paste a transaction id (64 hexadecimal characters) or an explorer link to one."
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

    /// The transaction id in `text`: a bare id, or the first 64-character
    /// hexadecimal run in something pasted, such as an explorer link.
    public static func transactionID(in text: String) -> String? {
        text.lowercased().split(whereSeparator: { !$0.isHexDigit }).first { $0.count == 64 }.map(String.init)
    }

    /// `sources`, plus Koios's public API, without a key, for each public
    /// network that has no Blockfrost or Koios provider of its own. Koios
    /// serves anonymous requests at a lower rate, which is plenty for looking
    /// one transaction up.
    public static func withPublicFallback(_ sources: [Source]) -> [Source] {
        let covered = Set(sources.filter { $0.provider.kind == .blockfrost || $0.provider.kind == .koios }.map(\.provider.network))
        let fallback = CardanoNetwork.allCases.filter { !covered.contains($0) }.map {
            Source(provider: ProviderConfiguration(name: "Koios (public)", kind: .koios, network: $0), apiKey: nil)
        }
        return sources + fallback
    }

    /// The transaction with id `hash` (or an explorer link to it), from
    /// whichever source has it first, as the exact bytes on chain. Only
    /// Blockfrost and Koios can look transactions up; other sources are
    /// skipped.
    public func fetch(hash: String, from sources: [Source]) async throws -> FetchedTransaction {
        guard let found = Self.transactionID(in: hash), let id = try? TransactionId(from: .string(found)) else {
            throw FetchError.notAHash
        }
        let usable = sources.filter { $0.provider.kind == .blockfrost || $0.provider.kind == .koios }
        guard !usable.isEmpty else { throw FetchError.noProviders }

        return try await withThrowingTaskGroup(of: Result<FetchedTransaction, FetchFailure>.self) { group in
            for source in usable {
                group.addTask {
                    do {
                        let context = try await makeContext(source.provider, source.apiKey)
                        // The bytes as submitted: decoding and encoding again
                        // could change a non-canonical transaction's id.
                        let cbor = try await context.transactionCBOR(hash: id)
                        return .success(FetchedTransaction(cbor: cbor, network: source.provider.network))
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
