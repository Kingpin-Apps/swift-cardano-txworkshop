import SwiftUI
import TxWorkshopCore

/// Replaces the document's transaction with one looked up by id. The
/// replacement can be undone.
struct FetchByHashSheet: View {
    let document: TxWorkshopDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                FetchByHashSection(document: document, onFetched: { dismiss() })
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Fetch by ID", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 240)
        #endif
    }
}
