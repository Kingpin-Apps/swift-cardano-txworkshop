import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Signatures collected so far, with ways to get more from co-signers.
struct WitnessesSection: View {
    let document: TxWorkshopDocument
    let onImport: () -> Void

    var body: some View {
        Section {
            ForEach(document.content.witnesses) { witness in
                VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                    Text(verbatim: witness.label)
                    TWBytesText(witness.keyHash, font: TWFont.bytesSmall)
                        .foregroundStyle(TWColor.secondaryText)
                    Text(witness.addedAt, format: .dateTime)
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
            Button(action: onImport) {
                Label {
                    Text("Add a Co-signer's Witness…", bundle: #bundle)
                } icon: {
                    Image(systemName: "person.badge.plus")
                }
            }
            if let bytes = document.content.transaction {
                ShareTransactionLink(transaction: bytes, envelope: document.content.envelope)
            }
        } header: {
            Text("Witnesses", bundle: #bundle)
        } footer: {
            Text("Share the transaction with co-signers, then add the witnesses they send back.", bundle: #bundle)
        }
    }
}

/// Pastes a witness, checks it signs this transaction, and adds it.
struct ImportWitnessSheet: View {
    let document: TxWorkshopDocument
    /// The document window's; a sheet's own is not the document's on macOS.
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $label) { Text("Who it is from", bundle: #bundle) }
                    TextEditor(text: $text)
                        .font(TWFont.bytesSmall)
                        .frame(minHeight: 100, maxHeight: 220)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Text("Witness", bundle: #bundle))
                } footer: {
                    Text("A witness set or witness in CBOR hex, or a cardano-cli witness file.", bundle: #bundle)
                }
                if let problem {
                    Section { Text(verbatim: problem).foregroundStyle(TWColor.failure) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Add Witness", bundle: #bundle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: add) { Text("Add", bundle: #bundle) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 380)
        #endif
    }

    private func add() {
        guard let bytes = document.content.transaction else { return }
        do {
            let witnesses = try WitnessAssembler.witnesses(from: text)
            let bad = witnesses.filter { !WitnessAssembler.verifies($0, for: bytes) }
            guard bad.isEmpty else {
                problem = String(localized: "That witness does not sign this transaction: it was made for different bytes.", bundle: #bundle)
                return
            }
            let signed = try WitnessAssembler.merge(bytes, adding: witnesses)
            let name = label.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Co-signer", bundle: #bundle) : label
            let records = try witnesses.map { witness in
                CollectedWitness(label: name, keyHash: try WitnessAssembler.keyHash(witness), witnessCBOR: try WitnessAssembler.cborHex(witness), addedAt: .now)
            }
            document.update({ content in
                content.transaction = signed
                content.envelope = nil
                content.witnesses += records
            }, actionName: LocalizedStringResource("Add Witness", bundle: #bundle), undoManager: undoManager)
            dismiss()
        } catch {
            problem = String(describing: error)
        }
    }
}
