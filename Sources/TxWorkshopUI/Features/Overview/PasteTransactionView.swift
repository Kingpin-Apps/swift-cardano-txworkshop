import SwiftUI
import TxWorkshopCore

/// Takes a transaction pasted as hex, base64 or a text envelope.
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
                    .foregroundStyle(TWColor.failure)
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
                Text("Hex, base64, or a cardano-cli text envelope. You can also open a .tx, .signed or .cbor file.", bundle: #bundle)
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .navigationTitle(Text("Overview", bundle: #bundle))
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
