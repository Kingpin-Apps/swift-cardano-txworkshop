import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import SwiftCardanoUPLC
import TxWorkshopCore

/// Runs every script of a transaction with the protocol parameters' cost
/// models and the network's slot timeline, and says what each redeemer's
/// outcome means. The findings follow swift-cardano-txvalidator's phase 2,
/// which needs a live chain context for its cost models and timeline.
enum PhaseTwoRun {
    struct Result {
        let redeemers: [RedeemerOutcome]
        let findings: [ValidationFinding]
    }

    static func timeline(_ network: CardanoNetwork?) -> SlotTimeline? {
        switch network {
        case .mainnet: .mainnet
        case .preprod: .preprod
        case .preview: .preview
        default: nil
        }
    }

    static func evaluate(
        transaction: Transaction, utxos: [UTxO], parameters: ProtocolParameters, network: CardanoNetwork?, view: TransactionView
    ) async throws -> Result {
        let phaseTwo = try PhaseTwo(protocolParameters: parameters, slotTimeline: timeline(network))
        let result = try await phaseTwo.evaluate(transaction: transaction, resolvedInputs: utxos)
        let declared = PhaseTwo.redeemers(of: transaction)

        var outcomes: [RedeemerOutcome] = []
        var findings: [ValidationFinding] = []
        for run in result.redeemers {
            let redeemer = declared.indices.contains(run.index) ? declared[run.index] : nil
            let described = view.redeemers.first { $0.position == run.index }
            let error = run.error.map { "\($0)" } ?? (run.passed ? nil : "Script execution failed (no error detail available).")
            let outcome = RedeemerOutcome(
                position: run.index,
                tag: described?.tag ?? "redeemer",
                index: described?.index ?? run.index,
                purpose: described?.purpose,
                passed: run.passed,
                consumed: run.budgetMeasured ? run.consumedBudget.map { .init(memory: $0.mem, steps: $0.cpu) } : nil,
                declared: redeemer?.exUnits.map { .init(memory: Int64($0.mem), steps: Int64($0.steps)) },
                logs: run.logs,
                error: error
            )
            outcomes.append(outcome)

            let path = "transaction_witness_set.redeemers[\(run.index)]"
            if !run.passed {
                let unresolved = error?.contains("Unresolved spent input") ?? false
                let unprepared = error?.contains("could not be prepared for evaluation") ?? false
                let hint = unresolved
                    ? "An input it needs is not in the chain data. Fetch chain data with Blockfrost or Koios, which can look up spent outputs, or add the UTxO by hand."
                    : unprepared
                        ? "The script never ran: it could not be found, decoded or given a script context. Check the witness set and reference inputs."
                        : "Check the script's logic, the redeemer and the datum it was given; the trace below shows how far it got."
                let logs = run.logs.isEmpty ? "" : " Traces: \(run.logs.joined(separator: "; "))"
                findings.append(ValidationFinding(
                    phase: 2, kind: "plutusScriptFailed", fieldPath: path,
                    message: "The \(outcome.tag) \(outcome.index) script failed: \(error ?? "")\(logs)", hint: hint, isWarning: false
                ))
            } else if outcome.exceedsDeclared, let consumed = outcome.consumed, let declared = outcome.declared {
                findings.append(ValidationFinding(
                    phase: 2, kind: "executionBudgetExceeded", fieldPath: path,
                    message: "The \(outcome.tag) \(outcome.index) script needs \(consumed.memory) memory and \(consumed.steps) steps, more than the \(declared.memory) and \(declared.steps) it declares. The ledger stops it at its declared units.",
                    hint: "Raise the redeemer's execution units to at least what the script uses, and the fee with them.", isWarning: false
                ))
            } else if let consumed = outcome.consumed, let declared = outcome.declared,
                declared.memory > consumed.memory * 2 || declared.steps > consumed.steps * 2
            {
                findings.append(ValidationFinding(
                    phase: 2, kind: "excessiveExecutionUnits", fieldPath: path,
                    message: "The \(outcome.tag) \(outcome.index) redeemer declares more than twice what its script uses (\(declared.memory) memory and \(declared.steps) steps declared, \(consumed.memory) and \(consumed.steps) used).",
                    hint: "Lower the declared units to what the script uses, plus a margin, to pay a smaller fee.", isWarning: true
                ))
            }
        }
        return Result(redeemers: outcomes, findings: findings)
    }
}
