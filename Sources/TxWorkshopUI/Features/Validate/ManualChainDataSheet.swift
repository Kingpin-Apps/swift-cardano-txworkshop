import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Chain data typed in: protocol parameters, the UTxOs of inputs the
/// document has none for, and the slot to judge at.
struct ManualChainDataSheet: View {
    let document: TxWorkshopDocument
    let missingInputs: [String]
    /// The document window's; a sheet's own is not the document's on macOS.
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var parameters: String
    @State private var utxos: [InputEntry]
    @State private var slot: String
    @State private var problems: [String] = []

    init(document: TxWorkshopDocument, missingInputs: [String], undoManager: UndoManager?) {
        self.document = document
        self.missingInputs = missingInputs
        self.undoManager = undoManager
        parameters = ManualChainData.protocolParametersText(document.content.chainContext?.protocolParameters)
        utxos = missingInputs.map { InputEntry(id: $0) }
        slot = document.content.chainContext?.tipSlot.map(String.init) ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $parameters)
                        .font(TWFont.bytesSmall)
                        .frame(minHeight: 120, maxHeight: 240)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Text("Protocol parameters", bundle: #bundle))
                } header: {
                    Text("Protocol parameters", bundle: #bundle)
                } footer: {
                    Text("JSON with Blockfrost or Ogmios field names, as `cardano-cli query protocol-parameters` can give via a provider.", bundle: #bundle)
                }
                if !missingInputs.isEmpty {
                    Section {
                        ForEach($utxos) { $entry in
                            VStack(alignment: .leading, spacing: TWSpacing.xs) {
                                TWBytesText(entry.id, font: TWFont.bytesSmall)
                                TextField(text: $entry.hex) {
                                    Text("UTxO or output CBOR, hex", bundle: #bundle)
                                }
                                .font(TWFont.bytesSmall)
                                .autocorrectionDisabled()
                            }
                        }
                    } header: {
                        Text("Inputs without their UTxO", bundle: #bundle)
                    }
                }
                Section {
                    TextField(text: $slot) {
                        Text("Slot", bundle: #bundle)
                    }
                    .font(TWFont.figure)
                } header: {
                    Text("Current slot", bundle: #bundle)
                }
                if !problems.isEmpty {
                    Section {
                        ForEach(problems, id: \.self) { problem in
                            Text(verbatim: problem)
                                .foregroundStyle(TWColor.failure)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Chain Data", bundle: #bundle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Text("Save", bundle: #bundle) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 620)
        #endif
    }

    private func save() {
        var problems: [String] = []
        var snapshot = document.content.chainContext ?? ChainContextSnapshot(fetchedAt: .now, utxos: [])
        let text = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            do {
                snapshot.protocolParameters = try ManualChainData.protocolParameters(json: text)
            } catch {
                problems.append(String(describing: error))
            }
        }
        for entry in utxos where !entry.hex.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                snapshot.utxos.append(try ManualChainData.utxoHex(for: entry.id, cborHex: entry.hex))
            } catch {
                problems.append("\(entry.id): \(error)")
            }
        }
        let trimmedSlot = slot.trimmingCharacters(in: .whitespaces)
        if !trimmedSlot.isEmpty {
            if let value = UInt64(trimmedSlot) {
                snapshot.tipSlot = value
            } else {
                problems.append(String(localized: "The slot is a whole number.", bundle: #bundle))
            }
        }
        self.problems = problems
        guard problems.isEmpty else { return }
        snapshot.fetchedAt = .now
        document.update({ $0.chainContext = snapshot }, actionName: LocalizedStringResource("Enter Chain Data", bundle: #bundle), undoManager: undoManager)
        dismiss()
    }
}

/// A missing input and the CBOR typed for it.
private struct InputEntry: Identifiable {
    /// `<transaction id>#<index>`.
    let id: String
    var hex = ""
}
