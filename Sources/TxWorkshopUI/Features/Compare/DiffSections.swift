import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A comparison's verdict, then its changes by section.
struct DiffSections: View {
    let diff: TransactionDiff

    var body: some View {
        Section {
            Label {
                switch diff.relation {
                case .identical:
                    Text("The transactions are identical.", bundle: #bundle)
                case .sameBody:
                    Text("Same body and id. Only the witnesses differ, as between an unsigned transaction and its signed copy.", bundle: #bundle)
                case .different:
                    Text(AttributedString(localized: "Different transactions, with ^[\(diff.changes.count) change](inflect: true).", bundle: #bundle))
                }
            } icon: {
                Image(systemName: diff.relation == .different ? "arrow.left.arrow.right" : "equal.circle")
            }
        }
        ForEach(diff.sections, id: \.section) { section, changes in
            Section {
                ForEach(changes) { change in
                    ChangeRow(change: change)
                }
            } header: {
                Text(section.title)
            }
        }
    }

}

/// One change: what it was, and what it is now.
private struct ChangeRow: View {
    let change: TransactionDiff.Change

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            Text(verbatim: change.label)
                .lineLimit(2)
                .truncationMode(.middle)
            if let old = change.old {
                value(old, systemImage: "minus.circle", color: TWColor.failure)
                    .accessibilityLabel(Text("Was \(old)", bundle: #bundle))
            }
            if let new = change.new {
                value(new, systemImage: "plus.circle", color: TWColor.success)
                    .accessibilityLabel(Text("Now \(new)", bundle: #bundle))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String, systemImage: String, color: Color) -> some View {
        Label {
            Text(verbatim: text.isEmpty ? "—" : text)
                .font(TWFont.bytesSmall)
                .lineLimit(3)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
    }
}

extension TransactionFact.Section {
    var title: LocalizedStringResource {
        switch self {
        case .transaction: LocalizedStringResource("Transaction", bundle: #bundle)
        case .inputs: LocalizedStringResource("Inputs", bundle: #bundle)
        case .referenceInputs: LocalizedStringResource("Reference Inputs", bundle: #bundle)
        case .collateral: LocalizedStringResource("Collateral", bundle: #bundle)
        case .outputs: LocalizedStringResource("Outputs", bundle: #bundle)
        case .mint: LocalizedStringResource("Minted & Burned", bundle: #bundle)
        case .withdrawals: LocalizedStringResource("Withdrawals", bundle: #bundle)
        case .certificates: LocalizedStringResource("Certificates", bundle: #bundle)
        case .votes: LocalizedStringResource("Votes", bundle: #bundle)
        case .proposals: LocalizedStringResource("Proposals", bundle: #bundle)
        case .scripts: LocalizedStringResource("Scripts", bundle: #bundle)
        case .redeemers: LocalizedStringResource("Redeemers", bundle: #bundle)
        case .datums: LocalizedStringResource("Datums", bundle: #bundle)
        case .metadata: LocalizedStringResource("Metadata", bundle: #bundle)
        case .witnesses: LocalizedStringResource("Witnesses", bundle: #bundle)
        }
    }
}
