import SwiftUI
import TxWorkshopCore
import UniformTypeIdentifiers

/// Takes a transaction for an empty document: pasted as hex, base64 or a
/// text envelope, fetched by id, or dropped as a file.
struct PasteTransactionView: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager
    @State private var text = ""
    @State private var problem: String?

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
                Button {
                    decode()
                } label: {
                    Text("Open Transaction", bundle: #bundle)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Paste a transaction", bundle: #bundle)
            } footer: {
                Text("Hex, base64, or a cardano-cli text envelope. You can also drop a .tx, .signed, .cbor or .hex file here.", bundle: #bundle)
            }
            FetchByHashSection(document: document)
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
        guard let type = UTType(filenameExtension: url.pathExtension),
            let format = TxDocumentFormat(contentType: type), format != .package,
            let data = try? Data(contentsOf: url),
            let dropped = try? TxDocumentCodec.content(fromFile: data, format: format)
        else {
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
