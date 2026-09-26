import Foundation
import TxWorkshopCore

/// A validation written out for people (Markdown) or programs (JSON).
public struct ValidationReport: Sendable {
    public let transactionID: String
    public let network: CardanoNetwork?
    public let outcome: ValidationOutcome

    public init(transactionID: String, network: CardanoNetwork?, outcome: ValidationOutcome) {
        self.transactionID = transactionID
        self.network = network
        self.outcome = outcome
    }

    public func markdown() -> String {
        var lines = ["# Validation of \(transactionID)", ""]
        if let network { lines.append("Network: \(network.id)  ") }
        lines.append("Judged \(outcome.mode == .now ? "as if submitted now" : "as written"), on \(outcome.ranAt.formatted(.iso8601)).")
        lines += ["", outcome.isValid
            ? "**Valid**, with \(outcome.warnings.count) warning\(outcome.warnings.count == 1 ? "" : "s")."
            : "**Not valid**: \(outcome.errors.count) error\(outcome.errors.count == 1 ? "" : "s"), \(outcome.warnings.count) warning\(outcome.warnings.count == 1 ? "" : "s")."]
        for (phase, title) in [(1, "Ledger rules"), (2, "Scripts")] {
            let findings = outcome.issues.filter { $0.phase == phase }
            guard !findings.isEmpty else { continue }
            lines += ["", "## \(title)", ""]
            for finding in findings {
                lines.append("- **\(finding.isWarning ? "Warning" : "Error")** `\(finding.kind)` at `\(finding.fieldPath)`: \(finding.message)")
                if let hint = finding.hint { lines.append("  - Hint: \(hint)") }
            }
        }
        if !outcome.redeemers.isEmpty {
            lines += ["", "## Script budgets", "", "| Redeemer | Result | Memory used / declared | Steps used / declared |", "| --- | --- | --- | --- |"]
            for redeemer in outcome.redeemers {
                func budget(_ used: Int64?, _ declared: Int64?) -> String {
                    "\(used.map(String.init) ?? "—") / \(declared.map(String.init) ?? "—")"
                }
                lines.append("| \(redeemer.tag) \(redeemer.index) | \(redeemer.passed ? "passed" : "failed") | \(budget(redeemer.consumed?.memory, redeemer.declared?.memory)) | \(budget(redeemer.consumed?.steps, redeemer.declared?.steps)) |")
            }
            for redeemer in outcome.redeemers where !redeemer.logs.isEmpty || redeemer.error != nil {
                lines += ["", "### \(redeemer.tag) \(redeemer.index)", ""]
                if let error = redeemer.error { lines.append("Error: `\(error)`") }
                if !redeemer.logs.isEmpty {
                    lines += ["", "```"] + redeemer.logs + ["```"]
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private struct Export: Encodable {
        let transactionID: String
        let network: String?
        let outcome: ValidationOutcome
        let isValid: Bool
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Export(transactionID: transactionID, network: network?.id, outcome: outcome, isValid: outcome.isValid))
    }
}
