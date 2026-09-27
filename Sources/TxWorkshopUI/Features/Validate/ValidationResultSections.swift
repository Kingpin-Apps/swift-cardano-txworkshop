import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A validation's verdict, its findings by phase, and each script's run.
struct ValidationResultSections: View {
    let outcome: ValidationOutcome
    let onShow: (String) -> Void
    let onTrace: (Int) -> Void

    var body: some View {
        Section {
            Label {
                if outcome.isValid {
                    Text(AttributedString(localized: "Valid, with ^[\(outcome.warnings.count) warning](inflect: true).", bundle: #bundle))
                } else {
                    Text(AttributedString(localized: "Not valid: ^[\(outcome.errors.count) error](inflect: true) and ^[\(outcome.warnings.count) warning](inflect: true).", bundle: #bundle))
                }
            } icon: {
                Image(systemName: outcome.isValid ? "checkmark.seal" : "xmark.seal")
            }
            .labelStyle(.status(outcome.isValid ? TWColor.success : TWColor.failure))
            TWFieldRow(LocalizedStringResource("Ran", bundle: #bundle)) {
                Text(outcome.ranAt, format: .relative(presentation: .named))
            }
        }
        ForEach([1, 2], id: \.self) { phase in
            let findings = outcome.issues.filter { $0.phase == phase }
            if !findings.isEmpty {
                Section {
                    ForEach(findings) { finding in
                        FindingRow(finding: finding, onShow: onShow)
                    }
                } header: {
                    if phase == 1 {
                        Text("Ledger rules", bundle: #bundle)
                    } else {
                        Text("Scripts", bundle: #bundle)
                    }
                }
            }
        }
        if !outcome.redeemers.isEmpty {
            Section {
                ForEach(outcome.redeemers) { redeemer in
                    RedeemerBudgetRow(redeemer: redeemer) { onTrace(redeemer.position) }
                }
            } header: {
                Text("Script budgets", bundle: #bundle)
            }
        }
    }
}

struct FindingRow: View {
    let finding: ValidationFinding
    /// Opens the CBOR explorer at the finding's item; `nil` where it is
    /// already shown.
    var onShow: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            Label {
                Text(verbatim: finding.title)
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: finding.isWarning ? "exclamationmark.triangle" : "xmark.octagon")
                    .foregroundStyle(finding.isWarning ? TWColor.warning : TWColor.failure)
                    .accessibilityLabel(finding.isWarning ? Text("Warning", bundle: #bundle) : Text("Error", bundle: #bundle))
            }
            Text(verbatim: finding.message)
                .textSelection(.enabled)
            if let hint = finding.hint {
                Label {
                    Text(verbatim: hint)
                } icon: {
                    Image(systemName: "lightbulb")
                }
                .font(.callout)
                .foregroundStyle(TWColor.secondaryText)
            }
            HStack {
                Text(verbatim: finding.fieldPath)
                    .font(TWFont.bytesSmall)
                    .foregroundStyle(TWColor.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let onShow, finding.fieldPath.hasPrefix("transaction_") {
                    Button {
                        onShow(finding.fieldPath)
                    } label: {
                        Text("Show in CBOR", bundle: #bundle)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

extension ValidationFinding {
    /// The kind as words: `feeTooSmall` becomes "Fee too small".
    var title: String {
        var words = ""
        for character in kind {
            if character.isUppercase, !words.isEmpty { words += " " }
            words.append(character)
        }
        return words.prefix(1).uppercased() + words.dropFirst().lowercased()
    }
}
