import SwiftUI
import UniformTypeIdentifiers
import TxWorkshopCore
import TxWorkshopEngine

/// One collected witness, saved or shared for whoever assembles the
/// transaction: a cardano-cli witness file, CBOR or CBOR hex.
struct WitnessExportMenu: View {
    let witness: CollectedWitness
    /// Saves `data` as `type`, named `name`, through the section's exporter.
    let save: (_ data: Data, _ type: UTType, _ name: String) -> Void
    let onProblem: (String) -> Void
    @State private var pendingShare: PendingShare?

    var body: some View {
        Menu {
            if let file = file(.textEnvelope) {
                ShareFileItem(file: WitnessFile(data: file, name: name), pending: $pendingShare) {
                    Label {
                        Text("Share Witness…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            Button {
                Clipboard.copy(witness.witnessCBOR)
            } label: {
                Label {
                    Text("Copy CBOR Hex", bundle: #bundle)
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }
            Section {
                Button {
                    export(.textEnvelope, as: .cardanoWitness)
                } label: {
                    Label {
                        Text("Witness File (.witness)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.badge.gearshape")
                    }
                }
                Button {
                    export(.cbor, as: .cardanoTransactionCBOR)
                } label: {
                    Label {
                        Text("CBOR (.cbor)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.zipper")
                    }
                }
                Button {
                    export(.hex, as: .cardanoTransactionHex)
                } label: {
                    Label {
                        Text("CBOR Hex (.hex)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "number")
                    }
                }
            } header: {
                Text("Save", bundle: #bundle)
            }
        } label: {
            Label {
                Text("Export \(witness.label)'s Witness", bundle: #bundle)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
            .labelStyle(.iconOnly)
            .twHitTarget()
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.borderless)
        .sharePicker($pendingShare)
        .help(Text("Save or share this witness for whoever assembles the transaction", bundle: #bundle))
        .accessibilityIdentifier("exportWitness-\(witness.keyHash)")
    }

    private var name: String { WitnessExport.fileName(for: witness.label) }

    private func file(_ format: WitnessExport.Format) -> Data? {
        try? WitnessExport.file(try WitnessExport.witness(witness), format: format)
    }

    private func export(_ format: WitnessExport.Format, as type: UTType) {
        do {
            save(try WitnessExport.file(try WitnessExport.witness(witness), format: format), type, name)
        } catch {
            onProblem(String(describing: error))
        }
    }
}

/// The transaction and its witnesses, for co-signers and whoever assembles
/// it: shared or saved as it is, saved without its signatures, or every
/// witness copied as one witness set.
struct CoSigningExportMenu: View {
    let document: TxWorkshopDocument
    let transaction: Data
    let save: (_ data: Data, _ type: UTType, _ name: String) -> Void
    let onProblem: (String) -> Void
    @State private var pendingShare: PendingShare?

    var body: some View {
        Menu {
            if let shared {
                ShareFileItem(file: shared, pending: $pendingShare) {
                    Label {
                        Text("Share Transaction…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            Section {
                Button {
                    if let shared { save(shared.data, .cardanoTextEnvelope, shared.name) }
                } label: {
                    Label {
                        Text("Transaction for Co-signers (.tx)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.badge.gearshape")
                    }
                }
                .disabled(shared == nil)
                Button(action: saveUnsigned) {
                    Label {
                        Text("Unsigned Transaction (.tx)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.badge.clock")
                    }
                }
            } header: {
                Text("Save", bundle: #bundle)
            }
            if !document.content.witnesses.isEmpty {
                Button(action: copyWitnessSet) {
                    Label {
                        Text("Copy All Witnesses as a Witness Set", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        } label: {
            Label {
                Text("Share & Export for Co-signers", bundle: #bundle)
            } icon: {
                Image(systemName: "square.and.arrow.up.on.square")
            }
        }
        .sharePicker($pendingShare)
        .help(Text("Share the transaction with co-signers, or save it, with or without its signatures, for whoever assembles it", bundle: #bundle))
        .accessibilityIdentifier("coSigningExport")
    }

    /// The transaction as it is, signatures and all, as a text envelope:
    /// what a co-signer passes to `transaction witness --tx-body-file`.
    private var shared: TextEnvelopeFile? {
        let content = TxDocumentContent(transaction: transaction, envelope: document.content.envelope)
        guard let data = try? TxDocumentCodec.file(for: content, format: .textEnvelope) else { return nil }
        return TextEnvelopeFile(data: data, name: String(localized: "Transaction", bundle: #bundle))
    }

    /// The body with no key witnesses: what `transaction assemble
    /// --tx-body-file` takes, with each `.witness` file beside it.
    private func saveUnsigned() {
        do {
            let data = try TxDocumentCodec.textEnvelope(try WitnessExport.unsigned(transaction))
            save(data, .cardanoTextEnvelope, String(localized: "Unsigned Transaction", bundle: #bundle))
        } catch {
            onProblem(String(describing: error))
        }
    }

    private func copyWitnessSet() {
        do {
            Clipboard.copy(try WitnessExport.witnessSetHex(try document.content.witnesses.map(WitnessExport.witness)))
        } catch {
            onProblem(String(describing: error))
        }
    }
}

/// A witness as a `.witness` file, to share.
struct WitnessFile: ShareableFile {
    let data: Data
    let name: String
    var fileName: String { name + ".witness" }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .cardanoWitness) { file in
            SentTransferredFile(try TransferredFileDraft.write(file.data, named: file.fileName))
        }
    }
}

/// Writes shared bytes to a named temporary file, so the receiving app gets
/// a real file with the right name and extension rather than raw data.
enum TransferredFileDraft {
    static func write(_ data: Data, named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
