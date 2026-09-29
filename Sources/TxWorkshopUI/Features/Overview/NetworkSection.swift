import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Speaks up when the transaction's addresses point to another network than
/// the document's, or it has none yet. The network itself is chosen in the
/// toolbar.
struct NetworkSection: View {
    let document: TxWorkshopDocument

    var body: some View {
        if let transaction = document.content.transaction,
            let hint = NetworkGuess.hint(forTransaction: transaction),
            !hint.fits(document.content.network)
        {
            Section {
                NetworkSuggestion(document: document, hint: hint, source: Text("The transaction's addresses", bundle: #bundle))
            }
        }
    }
}
