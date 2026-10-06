import SwiftUI
import TxWorkshopCore

/// Replaces the document's transaction with another: pasted, opened from or
/// dropped as a file, or fetched by id. The replacement can be undone.
struct ReplaceTransactionSheet: View {
    let document: TxWorkshopDocument
    /// The document window's; a sheet's own is not the document's on macOS.
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var dropProblem: String?

    var body: some View {
        NavigationStack {
            Form {
                TransactionSourceSection(document: document, onLoaded: { dismiss() }, documentUndoManager: undoManager)
                FetchByHashSection(document: document, onFetched: { dismiss() }, documentUndoManager: undoManager)
                if let dropProblem {
                    Section { TWErrorText(dropProblem) }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                dropProblem = TransactionSourceSection.load(url, into: document, undoManager: undoManager) { dismiss() }
                return dropProblem == nil
            }
            .formStyle(.grouped)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle(Text("Replace Transaction", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 480)
        #endif
    }
}
