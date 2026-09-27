import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// One script run: pass or fail, what it used against what its redeemer
/// declares, and its traces.
struct RedeemerBudgetRow: View {
    let redeemer: RedeemerOutcome
    let onTrace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.s) {
            HStack {
                Label {
                    Text(verbatim: "\(redeemer.tag) \(redeemer.index)")
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: redeemer.passed ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(redeemer.passed ? TWColor.success : TWColor.failure)
                        .accessibilityLabel(redeemer.passed ? Text("Passes", bundle: #bundle) : Text("Fails", bundle: #bundle))
                }
                Spacer()
                if let purpose = redeemer.purpose {
                    Text(verbatim: purpose)
                        .font(TWFont.bytesSmall)
                        .foregroundStyle(TWColor.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let consumed = redeemer.consumed {
                BudgetBar(
                    title: LocalizedStringResource("Memory", bundle: #bundle),
                    used: consumed.memory, declared: redeemer.declared?.memory
                )
                BudgetBar(
                    title: LocalizedStringResource("Steps", bundle: #bundle),
                    used: consumed.steps, declared: redeemer.declared?.steps
                )
            } else {
                Text("No budget: the protocol parameters have no cost model for this script.", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
            }
            if let error = redeemer.error {
                Text(verbatim: error)
                    .font(TWFont.bytesSmall)
                    .textSelection(.enabled)
            }
            Button(action: onTrace) {
                Label {
                    Text("Trace Timeline", bundle: #bundle)
                } icon: {
                    Image(systemName: "chart.xyaxis.line")
                }
            }
            .buttonStyle(.borderless)
            if !redeemer.logs.isEmpty {
                DisclosureGroup {
                    ForEach(redeemer.logs.enumerated(), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(TWFont.bytesSmall)
                            .textSelection(.enabled)
                    }
                } label: {
                    Text(AttributedString(localized: "^[\(redeemer.logs.count) trace](inflect: true)", bundle: #bundle))
                }
            }
        }
    }
}

/// What a script used of what its redeemer declares; over the declared
/// units shows in red, because the ledger stops the script there.
struct BudgetBar: View {
    let title: LocalizedStringResource
    let used: Int64
    let declared: Int64?

    private var isOver: Bool { declared.map { used > $0 } ?? false }
    private var fraction: Double {
        guard let declared, declared > 0 else { return 1 }
        return min(1, Double(used) / Double(declared))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                if let declared {
                    Text("\(used, format: .number) of \(declared, format: .number) (\(Double(used) / Double(max(declared, 1)), format: .percent.precision(.fractionLength(0))))", bundle: #bundle)
                        .font(TWFont.figure)
                        .foregroundStyle(isOver ? TWColor.failure : Color.primary)
                } else {
                    Text(used, format: .number)
                        .font(TWFont.figure)
                }
            }
            ProgressView(value: fraction)
                .tint(isOver ? TWColor.failure : fraction > 0.9 ? TWColor.warning : TWColor.success)
            if isOver, let declared {
                Text("Over by \(used - declared, format: .number): the ledger stops the script at its declared units.", bundle: #bundle)
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
