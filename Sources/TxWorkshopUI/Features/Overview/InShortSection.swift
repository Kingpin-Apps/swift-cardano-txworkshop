import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The plain-English sentence, set in the display serif: the first thing
/// read on the Overview. Its own view, so the sentence is only built again
/// when the inspection changes.
struct InShortSection: View {
    let inspection: TransactionInspection

    var body: some View {
        Section {
            Text(verbatim: TransactionDescription.sentence(for: inspection))
                .font(TWFont.displayTitle)
                .padding(.vertical, TWSpacing.xs)
        } header: {
            Text("In short", bundle: #bundle)
        }
    }
}
