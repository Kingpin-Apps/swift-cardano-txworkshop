import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import SwiftCardanoUPLC
import TxWorkshopCore

/// Validates a transaction from the chain data a document keeps, with no
/// connection: phase 1 through the validator's ledger rules, phase 2 by
/// running each script.
public struct TransactionValidation: Sendable {
    public init() {}

    /// The moment the transaction is judged at.
    public enum Mode: String, Sendable, Codable, CaseIterable {
        /// As if submitted now: at the tip the data was fetched at, with its
        /// inputs as spent as they were then.
        case now
        /// As the ledger saw it when it was written: inputs unspent, at a slot
        /// inside its validity window. For transactions already on chain.
        case asWritten
    }

    /// What the snapshot lacks for a full validation.
    public struct Requirements: Sendable, Equatable {
        public let needsProtocolParameters: Bool
        /// Inputs, as `<transaction id>#<index>`, the snapshot has no UTxO for.
        public let missingInputs: [String]
        /// Whether every input the snapshot knows is spent: the transaction
        /// is likely on chain already.
        public let allInputsSpent: Bool

        public var isComplete: Bool { !needsProtocolParameters && missingInputs.isEmpty }
    }

    public func requirements(for bytes: Data, snapshot: ChainContextSnapshot?) throws -> Requirements {
        let transaction = try Self.decode(bytes)
        let needed = TxValidator().necessaryData(transaction: transaction).inputs.map { "\($0.transactionId)#\($0.index)" }
        let known = Set(Self.utxos(snapshot).map { InputResolver.id($0.input) })
        let spent = Set(snapshot?.spentInputs ?? [])
        let spending = transaction.transactionBody.inputs.asArray.map(InputResolver.id)
        return Requirements(
            needsProtocolParameters: Self.protocolParameters(snapshot) == nil,
            missingInputs: needed.filter { !known.contains($0) },
            allInputsSpent: !spending.isEmpty && spending.allSatisfy(spent.contains)
        )
    }

    /// Runs both phases. Phase 2 runs only when the transaction has
    /// redeemers.
    @concurrent
    public func validate(
        _ bytes: Data, snapshot: ChainContextSnapshot, network: CardanoNetwork?, mode: Mode
    ) async throws -> ValidationOutcome {
        let transaction = try Self.decode(bytes)
        guard let parameters = Self.protocolParameters(snapshot) else { throw ValidationRunError.noProtocolParameters }
        let utxos = Self.utxos(snapshot)
        let ledger = LedgerState.decode(snapshot.ledgerState)
        let body = transaction.transactionBody

        let slot: UInt64? = switch mode {
        case .now: snapshot.tipSlot
        case .asWritten: body.validityStart.map { UInt64($0) } ?? body.ttl.map { UInt64(max(0, $0 - 1)) } ?? snapshot.tipSlot
        }
        let spent: [TransactionInput] = mode == .asWritten ? [] : (snapshot.spentInputs ?? []).compactMap(Self.input)
        let context = ValidationContext(
            resolvedInputs: utxos,
            spentInputRefs: spent,
            currentSlot: slot,
            network: network.map { $0 == .mainnet ? .mainnet : .testnet },
            accountContexts: ledger.accountContexts,
            poolContexts: ledger.poolContexts,
            drepContexts: ledger.drepContexts,
            govActionContexts: ledger.govActionContexts,
            lastEnactedGovAction: ledger.lastEnactedGovAction,
            currentCommitteeMembers: ledger.currentCommitteeMembers,
            potentialCommitteeMembers: ledger.potentialCommitteeMembers,
            treasuryValue: ledger.treasuryValue,
            currentEpoch: ledger.currentEpoch,
            era: ledger.era.flatMap(Era.init(rawValue:)).map { transaction.possibleEras.clamp($0) }
        )
        let phase1 = try await TxValidator().validatePhase1(transaction: transaction, protocolParams: parameters, context: context)
        let view = phase1.transactionView
        var issues = phase1.phase1Result.allIssues.map { ValidationFinding($0, phase: 1) }
        if mode == .asWritten {
            issues = issues.map(Self.asWritten)
        }

        var redeemers: [RedeemerOutcome] = []
        if transaction.transactionWitnessSet.redeemers != nil {
            let run = try await PhaseTwoRun.evaluate(
                transaction: transaction, utxos: utxos, parameters: parameters, network: network, view: view
            )
            redeemers = run.redeemers
            issues += run.findings
        }
        return ValidationOutcome(ranAt: .now, mode: mode, issues: issues, redeemers: redeemers)
    }

    /// The script data hash covers the cost models, and only today's
    /// protocol parameters can be fetched: judged as written, a transaction
    /// from before a cost model change no longer matches. That is expected,
    /// so it is a warning here.
    static func asWritten(_ finding: ValidationFinding) -> ValidationFinding {
        guard finding.kind == "scriptDataHashMismatch", !finding.isWarning else { return finding }
        return ValidationFinding(
            phase: finding.phase, kind: finding.kind, fieldPath: finding.fieldPath,
            message: finding.message + " Judged as written, this is expected if the cost models have changed since: the check uses today's protocol parameters.",
            hint: finding.hint, isWarning: true
        )
    }

    static func decode(_ bytes: Data) throws -> Transaction {
        do {
            return try Transaction.fromCBOR(data: bytes)
        } catch {
            throw InspectionError.malformed(String(describing: error))
        }
    }

    static func utxos(_ snapshot: ChainContextSnapshot?) -> [UTxO] {
        (snapshot?.utxos ?? []).compactMap { hex in
            (try? TxDocumentCodec.bytes(fromHex: hex)).flatMap { try? UTxO.fromCBOR(data: $0) }
        }
    }

    static func protocolParameters(_ snapshot: ChainContextSnapshot?) -> ProtocolParameters? {
        snapshot?.protocolParameters.flatMap { try? JSONDecoder().decode(ProtocolParameters.self, from: $0) }
    }

    static func input(_ id: String) -> TransactionInput? {
        let parts = id.split(separator: "#")
        guard parts.count == 2, let index = UInt16(parts[1]) else { return nil }
        return try? TransactionInput(from: String(parts[0]), index: index)
    }
}

public enum ValidationRunError: Error, Sendable, Equatable, CustomStringConvertible {
    case noProtocolParameters

    public var description: String {
        switch self {
        case .noProtocolParameters: "Validation needs the protocol parameters: fetch chain data, or paste them."
        }
    }
}

/// The verdict of one validation run.
public struct ValidationOutcome: Sendable, Equatable {
    public let ranAt: Date
    public let mode: TransactionValidation.Mode
    public let issues: [ValidationFinding]
    public let redeemers: [RedeemerOutcome]

    public var errors: [ValidationFinding] { issues.filter { !$0.isWarning } }
    public var warnings: [ValidationFinding] { issues.filter(\.isWarning) }
    public var isValid: Bool { errors.isEmpty }
}

/// One thing validation found.
public struct ValidationFinding: Sendable, Equatable, Identifiable {
    /// 1 for the ledger rules, 2 for scripts.
    public let phase: Int
    /// The validator's name for it, e.g. `feeTooSmall`.
    public let kind: String
    /// Where in the transaction, as the validator writes it:
    /// `transaction_body.outputs[1].address`.
    public let fieldPath: String
    public let message: String
    public let hint: String?
    public let isWarning: Bool
    public var id: String { "\(phase)|\(kind)|\(fieldPath)|\(message)" }

    init(_ error: ValidationError, phase: Int) {
        self.phase = phase
        kind = error.kind.rawValue
        fieldPath = error.fieldPath
        message = error.message
        hint = error.hint
        isWarning = error.isWarning
    }

    init(phase: Int, kind: String, fieldPath: String, message: String, hint: String?, isWarning: Bool) {
        self.phase = phase
        self.kind = kind
        self.fieldPath = fieldPath
        self.message = message
        self.hint = hint
        self.isWarning = isWarning
    }
}

/// How one redeemer's script ran.
public struct RedeemerOutcome: Sendable, Equatable, Identifiable {
    /// The redeemer's position in the witness set.
    public let position: Int
    public let tag: String
    public let index: Int
    public let purpose: String?
    public let passed: Bool
    /// What the script spent, when it ran with a real cost model.
    public let consumed: Budget?
    /// What the redeemer declares.
    public let declared: Budget?
    public let logs: [String]
    public let error: String?
    public var id: Int { position }

    public struct Budget: Sendable, Equatable {
        public let memory: Int64
        public let steps: Int64
    }

    /// Whether the script needs more than its redeemer declares; the ledger
    /// stops it at the declared units.
    public var exceedsDeclared: Bool {
        guard let consumed, let declared else { return false }
        return consumed.memory > declared.memory || consumed.steps > declared.steps
    }
}
