import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import TxWorkshopCore

/// A decoded transaction, summarised for display.
public struct TransactionSummary: Sendable, Equatable {
    public let id: String
    public let view: TransactionView
    /// The eras the transaction could have been written for, e.g. `babbage…conway`.
    public let possibleEras: String
    public let isSigned: Bool
    public let byteCount: Int
}

public enum InspectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case malformed(String)

    public var description: String {
        switch self {
        case .malformed(let reason): reason
        }
    }
}

/// Decodes transaction bytes and summarises them.
public struct TransactionInspector: Sendable {
    public init() {}

    /// The summary of `bytes`. Decoding a large transaction takes a while, so
    /// this runs off the caller's actor.
    @concurrent
    public func inspect(_ bytes: Data) async throws -> TransactionSummary {
        let transaction: Transaction
        do {
            transaction = try Transaction.fromCBOR(data: bytes)
        } catch {
            throw InspectionError.malformed(String(describing: error))
        }
        let view: TransactionView
        do {
            view = try TxValidator().inspect(transaction: transaction)
        } catch {
            throw InspectionError.malformed(String(describing: error))
        }
        return TransactionSummary(
            id: view.txId,
            view: view,
            possibleEras: view.possibleEras,
            isSigned: !transaction.transactionWitnessSet.isEmpty(),
            byteCount: bytes.count
        )
    }
}
