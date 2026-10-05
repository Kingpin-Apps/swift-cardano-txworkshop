import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A redeemer to run the script with instead: through its blueprint's form
/// when a blueprint knows it, or as raw Plutus data.
struct RedeemerEditSheet: View {
    let hex: String
    let form: BlueprintForm?
    let blueprints: [StoredBlueprint]
    let onRun: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var value: BlueprintValue = .data("")
    @State private var usesForm = false

    private var choice: BlueprintChoice? {
        form.flatMap { BlueprintCatalog.choice(for: $0, in: blueprints) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if choice != nil {
                    Picker(selection: $usesForm) {
                        Text("Form", bundle: #bundle).tag(true)
                        Text("Raw", bundle: #bundle).tag(false)
                    } label: {
                        Text("Enter as", bundle: #bundle)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    if usesForm, let choice, let schema = choice.validator.redeemer?.schema {
                        BlueprintValueEditor(
                            blueprint: choice.blueprint, schema: schema, value: $value, path: "redeemer",
                            label: choice.blueprint.typeName(schema) ?? "redeemer",
                            problems: Dictionary(
                                choice.blueprint.problems(value, as: schema, path: "redeemer").map { ($0.path, $0.message) },
                                uniquingKeysWith: { first, _ in first }
                            )
                        )
                    } else {
                        ValueField(kind: .plutusData, text: $text, prompt: Text("Plutus data (CBOR hex, JSON or a number)", bundle: #bundle), axis: .vertical)
                    }
                } footer: {
                    Text("The script runs with this redeemer in the debugger only; the transaction is not changed.", bundle: #bundle)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Edit Redeemer", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let edited {
                            onRun(edited)
                            dismiss()
                        }
                    } label: {
                        Text("Run", bundle: #bundle)
                    }
                    .disabled(edited == nil)
                    .accessibilityIdentifier("debugRunEdited")
                }
            }
            .onAppear {
                text = hex
                if let form {
                    value = form.value
                    usesForm = true
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 520)
        #endif
    }

    /// The edited redeemer as CBOR hex, or `nil` while it does not read.
    private var edited: String? {
        if usesForm, let choice, let schema = choice.validator.redeemer?.schema {
            return try? choice.blueprint.cborHex(value, as: schema, path: "redeemer")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? ValueReader.read(.plutusData, text: trimmed, network: nil).value
    }
}
