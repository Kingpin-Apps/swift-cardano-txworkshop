import SwiftUI
import UniformTypeIdentifiers
import TxWorkshopCore
import TxWorkshopEngine

/// Signatures collected so far, with ways to get more from co-signers.
struct WitnessesSection: View {
    let document: TxWorkshopDocument
    let onImport: () -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var problem: String?

    var body: some View {
        Section {
            ForEach(document.content.witnesses) { witness in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                        Text(verbatim: witness.label)
                        CopyableBytes(witness.keyHash)
                            .foregroundStyle(TWColor.secondaryText)
                        Text(witness.addedAt, format: .dateTime)
                            .font(.caption)
                            .foregroundStyle(TWColor.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    Button(role: .destructive) {
                        remove(witness)
                    } label: {
                        Label {
                            Text("Remove \(witness.label)'s Witness", bundle: #bundle)
                        } icon: {
                            Image(systemName: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .twHitTarget()
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Remove this witness from the transaction", bundle: #bundle))
                    .accessibilityIdentifier("removeWitness-\(witness.keyHash)")
                }
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
        if let problem {
            TWErrorText(problem)
        }
    }

    /// Takes the witness out of the transaction, and off the list.
    private func remove(_ witness: CollectedWitness) {
        guard let bytes = document.content.transaction else { return }
        do {
            let unsigned = try WitnessAssembler.remove(bytes, keyHashes: [witness.keyHash])
            document.update({ content in
                content.transaction = unsigned
                content.envelope = nil
                content.witnesses.removeAll { $0.keyHash == witness.keyHash }
            }, actionName: LocalizedStringResource("Remove Witness", bundle: #bundle), undoManager: undoManager)
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }
}

/// Pastes a witness, or reads it from a file, checks it signs this
/// transaction, and adds it.
struct ImportWitnessSheet: View {
    let document: TxWorkshopDocument
    /// The document window's; a sheet's own is not the document's on macOS.
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var text = ""
    @State private var problem: String?
    @State private var isImporting = false
    /// The name the last chosen file gave the witness, so the next file
    /// replaces it; a name typed in is kept.
    @State private var labelFromFile: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TWLabeledField(Text("Who it is from", bundle: #bundle), text: $label)
                    TextEditor(text: $text)
                        .font(TWFont.bytesSmall)
                        .frame(minHeight: 100, maxHeight: 220)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Text("Witness", bundle: #bundle))
                    Button {
                        isImporting = true
                    } label: {
                        Label {
                            Text("Choose File…", bundle: #bundle)
                        } icon: {
                            Image(systemName: "doc.badge.plus")
                        }
                    }
                    .accessibilityIdentifier("witnessFromFile")
                } footer: {
                    Text("A witness set or witness in CBOR hex, or a cardano-cli witness file: paste it, or choose the file.", bundle: #bundle)
                }
                if let problem {
                    Section { TWErrorText(problem) }
                }
            }
            .formStyle(.grouped)
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data, .json, .plainText]) { result in
                if case .success(let url) = result { load(url) }
            }
            .navigationTitle(Text("Add Witness", bundle: #bundle))
            .twSheetRoot()
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

    /// Puts a witness file's contents in the field, and names the witness
    /// after the file unless a name was typed.
    private func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            problem = String(localized: "\(url.lastPathComponent) could not be read.", bundle: #bundle)
            return
        }
        let file = Self.read(data, named: url.lastPathComponent, label: label, labelFromFile: labelFromFile)
        text = file.text
        label = file.label
        labelFromFile = file.label
        problem = file.isWitness
            ? nil
            : String(localized: "\(url.lastPathComponent) is not a witness: choose a cardano-cli witness file, or a witness in CBOR.", bundle: #bundle)
    }

    /// What a chosen witness file puts in the sheet: its text, as written, or
    /// raw CBOR as hex; and the witness's name, the file's without its
    /// extension, when the name is empty or came from an earlier file.
    static func read(_ data: Data, named fileName: String, label: String, labelFromFile: String?)
        -> (text: String, label: String, isWitness: Bool)
    {
        let asText = String(data: data, encoding: .utf8)
        let hex = TxDocumentCodec.hex(data)
        let text: String
        if let asText, (try? WitnessAssembler.witnesses(from: asText)) != nil {
            text = asText
        } else if (try? WitnessAssembler.witnesses(from: hex)) != nil {
            text = hex
        } else {
            // Neither: shown as written, so it is plain what was chosen.
            text = asText ?? hex
        }
        let typed = label.trimmingCharacters(in: .whitespaces)
        let name = typed.isEmpty || typed == labelFromFile ? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent : label
        return (text, name, (try? WitnessAssembler.witnesses(from: text)) != nil)
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
