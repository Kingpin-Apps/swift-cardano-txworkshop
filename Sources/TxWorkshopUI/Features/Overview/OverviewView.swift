import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The document's overview: what the transaction is at a glance, and notes.
/// An empty document asks for a transaction first.
struct OverviewView: View {
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>

    var body: some View {
        if document.content.transaction != nil {
            TransactionOverview(document: document, inspection: inspection)
        } else {
            PasteTransactionView(document: document)
        }
    }
}

#Preview("Empty") {
    NavigationStack { OverviewView(document: TxWorkshopDocument(), inspection: .idle) }
}

#Preview("Transaction") {
    NavigationStack { OverviewView(document: .preview, inspection: .loading) }
}
