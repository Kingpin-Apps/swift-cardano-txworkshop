import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Checks the transaction, or the selected item, against the ledger's CDDL
/// schema, and lists the mismatches. Tapping one selects its item.
struct SchemaPanel: View {
    let exploration: CBORExploration
    let selectedItem: CBORItem?
    let onSelectPath: ([Int]) -> Void
    @Binding var era: String
    @State private var target = Target.transaction
    @State private var rule = ""
    @State private var rules: [String] = []
    @State private var report: LoadState<SchemaReport> = .idle

    enum Target: Hashable { case transaction, selection }

    var body: some View {
        Form {
            Section {
                Picker(selection: $era) {
                    ForEach(SchemaCheck.eras, id: \.self) { era in
                        Text(verbatim: era.capitalized).tag(era)
                    }
                } label: {
                    Text("Era", bundle: #bundle)
                }
                Picker(selection: $target) {
                    Text("Whole transaction", bundle: #bundle).tag(Target.transaction)
                    Text("Selected item", bundle: #bundle).tag(Target.selection)
                } label: {
                    Text("Check", bundle: #bundle)
                }
                if target == .selection {
                    Picker(selection: $rule) {
                        ForEach(rules, id: \.self) { rule in
                            Text(verbatim: rule).tag(rule)
                        }
                    } label: {
                        Text("Rule", bundle: #bundle)
                    }
                }
                Button(action: check) {
                    Text("Check Against Schema", bundle: #bundle)
                        .opacity(report.isLoading ? 0 : 1)
                        .overlay { if report.isLoading { ProgressView() } }
                }
                .disabled(report.isLoading || (target == .selection && (selectedItem == nil || rule.isEmpty)))
            } footer: {
                if target == .selection, selectedItem == nil {
                    Text("Select an item in the tree first.", bundle: #bundle)
                } else {
                    Text("Uses the Cardano ledger's own CDDL for the era.", bundle: #bundle)
                }
            }
            switch report {
            case .idle, .loading:
                EmptyView()
            case .failed(let message):
                Section {
                    Label {
                        Text(verbatim: message)
                    } icon: {
                        Image(systemName: "xmark.octagon")
                    }
                    .foregroundStyle(TWColor.failure)
                }
            case .loaded(let report):
                SchemaReportSections(report: report, onSelectPath: onSelectPath)
            }
        }
        .formStyle(.grouped)
        .task(id: era) {
            rules = (try? SchemaCheck().ruleNames(era: era)) ?? []
            if !rules.contains(rule) {
                rule = rules.contains("transaction_body") ? "transaction_body" : rules.first ?? ""
            }
        }
        .onChange(of: exploration.id) { report = .idle }
    }

    private func check() {
        let bytes = exploration.bytes
        let era = era
        let rule = rule
        let item = target == .selection ? selectedItem : nil
        report = .loading
        Task {
            do {
                if let item {
                    report = .loaded(try await SchemaCheck().check(bytes, range: item.range, path: item.path, rule: rule, era: era))
                } else {
                    report = .loaded(try await SchemaCheck().checkTransaction(bytes, era: era))
                }
            } catch {
                report = .failed(String(describing: error))
            }
        }
    }
}

/// The verdict and the list of mismatches.
private struct SchemaReportSections: View {
    let report: SchemaReport
    let onSelectPath: ([Int]) -> Void

    var body: some View {
        Section {
            Label {
                if report.issues.isEmpty {
                    Text("Matches `\(report.rule)` in the \(report.era.capitalized) schema.", bundle: #bundle)
                } else if report.isValid {
                    Text("Matches as the ledger reads it. The schema alone refuses what is listed below.", bundle: #bundle)
                } else {
                    Text(AttributedString(localized: "^[\(report.issues.count) mismatch](inflect: true) with `\(report.rule)` in the \(report.era.capitalized) schema.", bundle: #bundle))
                }
            } icon: {
                Image(systemName: report.isValid ? "checkmark.seal" : "xmark.seal")
            }
            .foregroundStyle(report.isValid ? TWColor.success : TWColor.failure)
        }
        if !report.issues.isEmpty {
            Section {
                ForEach(report.issues) { issue in
                    Button {
                        if let path = issue.itemPath { onSelectPath(path) }
                    } label: {
                        SchemaIssueRow(issue: issue)
                    }
                    .buttonStyle(.plain)
                    .disabled(issue.itemPath == nil)
                }
            } header: {
                Text("Mismatches", bundle: #bundle)
            }
        }
    }
}

private struct SchemaIssueRow: View {
    let issue: SchemaIssue

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            Text(verbatim: issue.location.isEmpty ? "/" : issue.location)
                .font(TWFont.bytesSmall)
                .foregroundStyle(TWColor.secondaryText)
            Text(verbatim: issue.reason)
            if issue.ledgerAccepts {
                Text("The ledger accepts this: long Plutus byte strings are written in 64-byte chunks.", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(TWColor.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(issue.itemPath == nil ? Text("") : Text("Selects the item", bundle: #bundle))
    }
}
