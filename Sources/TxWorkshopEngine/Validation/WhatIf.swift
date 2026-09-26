import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import SwiftCardanoUPLC
import TxWorkshopCore

/// Runs a transaction's scripts again with redeemers or datums changed, to
/// see what the change does to each script's outcome and budget. Nothing is
/// written back to the document.
public struct WhatIf: Sendable {
    public init() {}

    /// A redeemer or datum as it stands, for editing.
    public struct Value: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable {
            /// The redeemer at this position in the witness set.
            case redeemer(position: Int, tag: String, index: Int)
            /// A datum in the witness set, by its hash.
            case datum(hash: String)
        }

        public let kind: Kind
        /// The Plutus data, as CBOR in hex.
        public let cborHex: String
        public var id: String {
            switch kind {
            case .redeemer(let position, _, _): "redeemer-\(position)"
            case .datum(let hash): "datum-\(hash)"
            }
        }
    }

    /// Changes to try: new Plutus data, as CBOR hex, by ``Value/id``.
    public typealias Edits = [String: String]

    /// One redeemer's run before and after the change.
    public struct Comparison: Sendable, Equatable, Identifiable {
        public let before: RedeemerOutcome
        public let after: RedeemerOutcome?
        public var id: Int { before.position }

        /// The change in memory and steps used; `nil` when either run was not
        /// measured.
        public var delta: RedeemerOutcome.Budget? {
            guard let old = before.consumed, let new = after?.consumed else { return nil }
            return .init(memory: new.memory - old.memory, steps: new.steps - old.steps)
        }
    }

    /// The redeemers and witness datums of `bytes`.
    public func values(of bytes: Data) throws -> [Value] {
        let transaction = try TransactionValidation.decode(bytes)
        let view = try TxValidator().inspect(transaction: transaction)
        let redeemers = PhaseTwo.redeemers(of: transaction).enumerated().map { position, redeemer in
            let described = view.redeemers.first { $0.position == position }
            return Value(
                kind: .redeemer(position: position, tag: described?.tag ?? "redeemer", index: described?.index ?? redeemer.index),
                cborHex: ((try? redeemer.data.toCBORData()) ?? Data()).hex
            )
        }
        let datums = (transaction.transactionWitnessSet.plutusData?.asList ?? []).map { datum in
            let cbor = (try? datum.toCBORData()) ?? Data()
            return Value(kind: .datum(hash: InspectionBuilder.blake2b256(cbor).hex), cborHex: cbor.hex)
        }
        return redeemers + datums
    }

    /// Runs the scripts as they are and with `edits`, and pairs the results.
    @concurrent
    public func compare(
        _ bytes: Data, edits: Edits, snapshot: ChainContextSnapshot, network: CardanoNetwork?
    ) async throws -> [Comparison] {
        let transaction = try TransactionValidation.decode(bytes)
        guard let parameters = TransactionValidation.protocolParameters(snapshot) else { throw ValidationRunError.noProtocolParameters }
        let utxos = TransactionValidation.utxos(snapshot)
        let view = try TxValidator().inspect(transaction: transaction)
        let edited = try Self.apply(edits, to: transaction)

        let before = try await PhaseTwoRun.evaluate(transaction: transaction, utxos: utxos, parameters: parameters, network: network, view: view)
        let after = try await PhaseTwoRun.evaluate(transaction: edited, utxos: utxos, parameters: parameters, network: network, view: view)
        return before.redeemers.map { old in
            Comparison(before: old, after: after.redeemers.first { $0.position == old.position })
        }
    }

    static func apply(_ edits: Edits, to transaction: Transaction) throws -> Transaction {
        var transaction = transaction
        func data(_ hex: String) throws -> PlutusData {
            do {
                return try PlutusData.fromCBOR(data: try TxDocumentCodec.bytes(fromHex: hex))
            } catch {
                throw WhatIfError.notPlutusData
            }
        }
        let redeemers = PhaseTwo.redeemers(of: transaction)
        if redeemers.indices.contains(where: { edits["redeemer-\($0)"] != nil }) {
            var changed: [any RedeemerProtocol] = []
            for (position, redeemer) in redeemers.enumerated() {
                var redeemer = redeemer
                if let hex = edits["redeemer-\(position)"] { redeemer.data = try data(hex) }
                changed.append(redeemer)
            }
            transaction.transactionWitnessSet.redeemers = .list(changed)
        }
        if let datums = transaction.transactionWitnessSet.plutusData?.asList, !datums.isEmpty {
            var changed = datums
            for (offset, datum) in datums.enumerated() {
                let hash = InspectionBuilder.blake2b256((try? datum.toCBORData()) ?? Data()).hex
                if let hex = edits["datum-\(hash)"] { changed[offset] = try data(hex) }
            }
            if changed != datums { transaction.transactionWitnessSet.plutusData = .list(changed) }
        }
        return transaction
    }
}

public enum WhatIfError: Error, Sendable, Equatable, CustomStringConvertible {
    case notPlutusData

    public var description: String {
        switch self {
        case .notPlutusData: "That is not Plutus data in CBOR hex."
        }
    }
}
