import SwiftUI
import TxWorkshopCore

/// The document's overview: what the transaction is at a glance, and notes.
/// An empty document asks for a transaction first.
struct OverviewView: View {
    let document: TxWorkshopDocument

    var body: some View {
        if let transaction = document.content.transaction {
            TransactionOverview(document: document, transaction: transaction)
        } else {
            PasteTransactionView(document: document)
        }
    }
}

#Preview("Empty") {
    NavigationStack { OverviewView(document: TxWorkshopDocument()) }
}

#Preview("Transaction") {
    NavigationStack { OverviewView(document: .preview) }
}
