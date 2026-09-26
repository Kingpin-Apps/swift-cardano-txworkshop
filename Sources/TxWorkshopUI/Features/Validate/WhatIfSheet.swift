import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Change redeemers or datums, run the scripts again, and compare each
/// script's outcome and budget. The document is not changed.
struct WhatIfSheet: View {
    let document: TxWorkshopDocument
    @Environment(\.dismiss) private var dismiss
    @State private var values: [EditableValue] = []
    @State private var comparison: LoadState<[WhatIf.Comparison]> = .idle

    struct EditableValue: Identifiable {
        let value: WhatIf.Value
        var hex: String
        var id: String { value.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach($values) { $entry in
                    Section {
                        TextEditor(text: $entry.hex)
                            .font(TWFont.bytesSmall)
                            .frame(minHeight: 60, maxHeight: 140)
                            .autocorrectionDisabled()
                            .accessibilityLabel(Text(verbatim: title(entry.value)))
                        if entry.hex != entry.value.cborHex {
                            Button {
                                entry.hex = entry.value.cborHex
                            } label: {
                                Text("Revert", bundle: #bundle)
                            }
                            .buttonStyle(.borderless)
                        }
                    } header: {
                        Text(verbatim: title(entry.value))
                    }
                }
                Section {
                    Button(action: run) {
                        Text("Run Scripts", bundle: #bundle)
                            .opacity(comparison.isLoading ? 0 : 1)
                            .overlay { if comparison.isLoading { ProgressView() } }
                    }
                    .disabled(comparison.isLoading || document.content.chainContext == nil)
                } footer: {
                    Text("Plutus data as CBOR hex. The scripts run against the document's chain data; nothing is saved.", bundle: #bundle)
                }
                switch comparison {
                case .idle, .loading:
                    EmptyView()
                case .failed(let message):
                    Section {
                        Text(verbatim: message)
                            .foregroundStyle(TWColor.failure)
                    }
                case .loaded(let rows):
                    Section {
                        ForEach(rows) { row in
                            ComparisonRow(comparison: row)
                        }
                    } header: {
                        Text("Before and after", bundle: #bundle)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("What If", bundle: #bundle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                }
            }
            .task {
                guard let bytes = document.content.transaction else { return }
                values = ((try? WhatIf().values(of: bytes)) ?? []).map { EditableValue(value: $0, hex: $0.cborHex) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 420, idealHeight: 640)
        #endif
    }

    private func title(_ value: WhatIf.Value) -> String {
        switch value.kind {
        case .redeemer(_, let tag, let index): String(localized: "Redeemer: \(tag) \(index)", bundle: #bundle)
        case .datum(let hash): String(localized: "Datum \(String(hash.prefix(16)))…", bundle: #bundle)
        }
    }

    private func run() {
        guard let bytes = document.content.transaction, let snapshot = document.content.chainContext else { return }
        let edits = Dictionary(uniqueKeysWithValues: values.filter { $0.hex != $0.value.cborHex }.map {
            ($0.id, $0.hex.filter { !$0.isWhitespace })
        })
        let network = document.content.network
        comparison = .loading
        Task {
            do {
                comparison = .loaded(try await WhatIf().compare(bytes, edits: edits, snapshot: snapshot, network: network))
            } catch {
                comparison = .failed(String(describing: error))
            }
        }
    }
}

/// One script's run before and after, with the change in its budget.
private struct ComparisonRow: View {
    let comparison: WhatIf.Comparison

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            Text(verbatim: "\(comparison.before.tag) \(comparison.before.index)")
                .fontWeight(.medium)
            HStack {
                outcome(comparison.before, label: Text("Before", bundle: #bundle))
                Spacer()
                if let after = comparison.after {
                    outcome(after, label: Text("After", bundle: #bundle))
                }
            }
            if let delta = comparison.delta {
                HStack(spacing: TWSpacing.m) {
                    DeltaText(title: LocalizedStringResource("Memory", bundle: #bundle), value: delta.memory)
                    DeltaText(title: LocalizedStringResource("Steps", bundle: #bundle), value: delta.steps)
                }
            }
            if let error = comparison.after?.error, comparison.after?.passed == false {
                Text(verbatim: error)
                    .font(TWFont.bytesSmall)
                    .foregroundStyle(TWColor.failure)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func outcome(_ run: RedeemerOutcome, label: Text) -> some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            HStack(spacing: TWSpacing.xs) {
                label.font(.caption).foregroundStyle(TWColor.secondaryText)
                Image(systemName: run.passed ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(run.passed ? TWColor.success : TWColor.failure)
                    .accessibilityLabel(run.passed ? Text("Passes", bundle: #bundle) : Text("Fails", bundle: #bundle))
            }
            if let consumed = run.consumed {
                Text("\(consumed.memory, format: .number) mem · \(consumed.steps, format: .number) steps", bundle: #bundle)
                    .font(TWFont.figure)
            }
        }
    }
}

private struct DeltaText: View {
    let title: LocalizedStringResource
    let value: Int64

    var body: some View {
        HStack(spacing: TWSpacing.xs) {
            Text(title).font(.caption).foregroundStyle(TWColor.secondaryText)
            Text(verbatim: (value > 0 ? "+" : "") + value.formatted())
                .font(TWFont.figure)
                .foregroundStyle(value > 0 ? TWColor.failure : value < 0 ? TWColor.success : Color.primary)
        }
    }
}
