import SwiftUI
import TxWorkshopCore
import UniformTypeIdentifiers

/// Takes a transaction for an empty document: pasted as hex, base64 or a
/// text envelope, opened from or dropped as a file, or fetched by id.
struct PasteTransactionView: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager
    @State private var text = ""
    @State private var problem: String?
    @State private var isImporting = false

    var body: some View {
        Form {
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
            FetchByHashSection(document: document)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: TxDocumentCodec.importableContentTypes) { result in
            if case .success(let url) = result { _ = load(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return load(url)
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .navigationTitle(Text("Overview", bundle: #bundle))
    }

    /// Reads a dropped transaction file.
    private func load(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let dropped: TxDocumentContent
        do {
            dropped = try TxDocumentCodec.content(fromDroppedFile: try Data(contentsOf: url), fileExtension: url.pathExtension)
        } catch TxDocumentError.notATextEnvelope {
            problem = String(localized: "That JSON file is not a cardano-cli text envelope: it needs a cborHex field.", bundle: #bundle)
            return false
        } catch TxDocumentError.notHex {
            problem = String(localized: "That file's transaction is not valid hex.", bundle: #bundle)
            return false
        } catch {
            problem = String(localized: "That file is not a transaction.", bundle: #bundle)
            return false
        }
        document.update({ content in
            content.transaction = dropped.transaction
            content.envelope = dropped.envelope
        }, actionName: LocalizedStringResource("Drop Transaction", bundle: #bundle), undoManager: undoManager)
        problem = nil
        return true
    }

    private func decode() {
        do {
            let pasted = try TxDocumentCodec.content(fromPastedText: text)
            document.update({ content in
                content.transaction = pasted.transaction
                content.envelope = pasted.envelope
            }, actionName: LocalizedStringResource("Paste Transaction", bundle: #bundle), undoManager: undoManager)
            problem = nil
        } catch {
            problem = String(localized: "That is not a transaction in hex, base64 or a text envelope.", bundle: #bundle)
        }
    }
}
