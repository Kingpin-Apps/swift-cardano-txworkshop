import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import UniformTypeIdentifiers

/// Takes a transaction pasted as hex, base64 or a text envelope, or opened
/// from a file. Used by an empty document and by Replace Transaction.
struct TransactionSourceSection: View {
    let document: TxWorkshopDocument
    /// Called once the transaction is in the document.
    var onLoaded: () -> Void = {}
    /// The document window's, from a sheet: a sheet's own is not the
    /// document's on macOS.
    var documentUndoManager: UndoManager?
    @Environment(\.undoManager) private var environmentUndoManager
    private var undoManager: UndoManager? { documentUndoManager ?? environmentUndoManager }
    @State private var text = ""
    @State private var problem: String?
    @State private var isImporting = false

    var body: some View {
        Section {
            TextField(text: $text, axis: .vertical) {
                Text("Hex, base64 or text envelope", bundle: #bundle)
            }
                .font(TWFont.bytesSmall)
                .lineLimit(8...)
                .autocorrectionDisabled()
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel(Text("Transaction", bundle: #bundle))
            if let problem {
                Label {
                    Text(verbatim: problem)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .labelStyle(.status(TWColor.failure))
            }
            HStack {
                Button {
                    decode()
                } label: {
                    Text("Open Transaction", bundle: #bundle)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label {
                        Text("Open from File…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.badge.plus")
                    }
                }
            }
        } header: {
            Text("Paste a transaction", bundle: #bundle)
        } footer: {
            Text("Hex, base64, or a cardano-cli text envelope. Or open or drop a transaction file: .tx, .signed, .json, .cbor or .hex.", bundle: #bundle)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: TxDocumentCodec.importableContentTypes) { result in
            if case .success(let url) = result { problem = Self.load(url, into: document, undoManager: undoManager, onLoaded: onLoaded) }
        }
    }

    private func decode() {
        do {
            let pasted = try TxDocumentCodec.content(fromPastedText: text)
            document.replaceTransaction(
                pasted, actionName: LocalizedStringResource("Paste Transaction", bundle: #bundle), undoManager: undoManager
            )
            problem = nil
            onLoaded()
        } catch {
            problem = String(localized: "That is not a transaction in hex, base64 or a text envelope.", bundle: #bundle)
        }
    }

    /// Reads a transaction file into `document`; what is wrong with it if it
    /// can't be.
    static func load(
        _ url: URL, into document: TxWorkshopDocument, undoManager: UndoManager?, onLoaded: () -> Void = {}
    ) -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let opened: TxDocumentContent
        do {
            opened = try TxDocumentCodec.content(fromDroppedFile: try Data(contentsOf: url), fileExtension: url.pathExtension)
        } catch TxDocumentError.notATextEnvelope {
            return String(localized: "That JSON file is not a cardano-cli text envelope: it needs a cborHex field.", bundle: #bundle)
        } catch TxDocumentError.notHex {
            return String(localized: "That file's transaction is not valid hex.", bundle: #bundle)
        } catch {
            return String(localized: "That file is not a transaction.", bundle: #bundle)
        }
        document.replaceTransaction(opened, actionName: LocalizedStringResource("Drop Transaction", bundle: #bundle), undoManager: undoManager)
        onLoaded()
        return nil
    }
}

extension TxWorkshopDocument {
    /// Makes `new`'s transaction the document's, keeping its network when it
    /// has one and the record only of witnesses the new transaction carries.
    /// The replacement can be undone.
    func replaceTransaction(_ new: TxDocumentContent, network: CardanoNetwork? = nil, actionName: LocalizedStringResource, undoManager: UndoManager?) {
        let carried = new.transaction.flatMap { try? WitnessAssembler.existing(in: $0) }
            .map { Set($0.compactMap { try? WitnessAssembler.keyHash($0) }) } ?? []
        update({ content in
            content.transaction = new.transaction
            content.envelope = new.envelope
            content.network = network ?? content.network ?? Self.network(of: new.transaction)
            content.witnesses.removeAll { !carried.contains($0.keyHash) }
        }, actionName: actionName, undoManager: undoManager)
    }

    /// The network a transaction is certainly for, to fill in an unknown one.
    static func network(of transaction: Data?) -> CardanoNetwork? {
        guard let transaction, case .network(let network)? = NetworkGuess.hint(forTransaction: transaction) else { return nil }
        return network
    }
}
