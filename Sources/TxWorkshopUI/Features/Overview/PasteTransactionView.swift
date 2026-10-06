import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Takes a transaction for an empty document: pasted as hex, base64 or a
/// text envelope, opened from or dropped as a file, or fetched by id.
struct PasteTransactionView: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Form {
            TransactionSourceSection(document: document)
            FetchByHashSection(document: document)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return TransactionSourceSection.load(url, into: document, undoManager: undoManager) == nil
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .navigationTitle(Text("Overview", bundle: #bundle))
    }
}
