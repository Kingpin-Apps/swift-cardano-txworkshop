import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import TxWorkshopCore

public enum ResolveError: Error, Sendable, Equatable, CustomStringConvertible {
    case noInputs
    /// None of the inputs could be looked up; the provider's reason.
    case failed(String)

    public var description: String {
        switch self {
        case .noInputs: "The transaction has no inputs to look up."
        case .failed(let reason): "The inputs could not be looked up. \(reason)"
        }
    }
}

/// The outputs a transaction's inputs point at, as one provider sees them.
public struct ResolvedInputs: Sendable, Equatable {
    /// Each found input's UTxO, as CBOR in hex.
    public let utxos: [String]
    /// The found inputs that are already spent, as `<transaction id>#<index>`.
    public let spent: [String]
    /// The inputs the provider does not know, as `<transaction id>#<index>`.
    /// Providers that only see unspent outputs report spent inputs here.
    public let missing: [String]
}

/// Looks up the outputs a transaction spends, references and puts up as
/// collateral.
public struct InputResolver: Sendable {
    public typealias ContextMaker = TransactionFetcher.ContextMaker

    private let makeContext: ContextMaker

    public init(makeContext: @escaping ContextMaker = { try await ChainContextFactory().makeContext(for: $0, apiKey: $1) }) {
        self.makeContext = makeContext
    }

    public func resolve(transaction bytes: Data, provider: ProviderConfiguration, apiKey: String?) async throws -> ResolvedInputs {
        let transaction: Transaction
        do {
            transaction = try Transaction.fromCBOR(data: bytes)
        } catch {
            throw InspectionError.malformed(String(describing: error))
        }
        let body = transaction.transactionBody
        var inputs = body.inputs.asArray
        inputs += body.referenceInputs?.asList ?? []
        inputs += body.collateral?.asList ?? []
        var seen = Set<String>()
        inputs = inputs.filter { seen.insert(Self.id($0)).inserted }
        guard !inputs.isEmpty else { throw ResolveError.noInputs }

        let context: any ChainContext
        do {
            context = try await makeContext(provider, apiKey)
        } catch {
            throw ResolveError.failed(String(describing: error))
        }
        let lookups = await withTaskGroup(of: (Int, Result<(UTxO, isSpent: Bool)?, any Error>).self) { group in
            for (position, input) in inputs.enumerated() {
                group.addTask {
                    do {
                        return (position, .success(try await context.utxo(input: input)))
                    } catch {
                        return (position, .failure(error))
                    }
                }
            }
            var results = [Result<(UTxO, isSpent: Bool)?, any Error>?](repeating: nil, count: inputs.count)
            for await (position, result) in group {
                results[position] = result
            }
            return results.compactMap(\.self)
        }

        var utxos: [String] = []
        var spent: [String] = []
        var missing: [String] = []
        var firstError: (any Error)?
        for (input, lookup) in zip(inputs, lookups) {
            switch lookup {
            case .success(let found?):
                utxos.append(try found.0.toCBORData().hex)
                if found.isSpent { spent.append(Self.id(input)) }
            case .success(nil):
                missing.append(Self.id(input))
            case .failure(let error):
                firstError = firstError ?? error
                missing.append(Self.id(input))
            }
        }
        if utxos.isEmpty, let firstError {
            throw ResolveError.failed(String(describing: firstError))
        }
        return ResolvedInputs(utxos: utxos, spent: spent, missing: missing)
    }

    static func id(_ input: TransactionInput) -> String {
        "\(input.transactionId.payload.hex)#\(input.index)"
    }
}
