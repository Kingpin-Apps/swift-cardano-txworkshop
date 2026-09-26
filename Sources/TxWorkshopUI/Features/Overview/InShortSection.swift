import SwiftUI
import TxWorkshopEngine

/// The plain-English sentence. Its own view, so the sentence is only built
/// again when the inspection changes.
struct InShortSection: View {
    let inspection: TransactionInspection

    var body: some View {
        Section {
            Text(verbatim: TransactionDescription.sentence(for: inspection))
        } header: {
            Text("In short", bundle: #bundle)
        }
    }
}
