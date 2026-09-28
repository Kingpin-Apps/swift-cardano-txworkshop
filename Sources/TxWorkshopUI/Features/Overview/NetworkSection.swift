import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The network the document's transaction is for.
struct NetworkSection: View {
    let document: TxWorkshopDocument

    var body: some View {
        Section {
            NetworkPicker(document: document)
            if let transaction = document.content.transaction, let hint = NetworkGuess.hint(forTransaction: transaction) {
                NetworkSuggestion(document: document, hint: hint, source: Text("The transaction's addresses", bundle: #bundle))
            }
        } footer: {
            Text("Places the validity window in time, and picks the provider used for this transaction.", bundle: #bundle)
        }
    }
}
