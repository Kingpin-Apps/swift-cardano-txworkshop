import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Shows `content` once the document's transaction is inspected, and the
/// empty, loading and failure states until then.
struct InspectionContainer<Content: View>: View {
    let inspection: LoadState<TransactionInspection>
    let title: LocalizedStringResource
    @ViewBuilder let content: (TransactionInspection) -> Content

    var body: some View {
        Group {
            switch inspection {
            case .idle:
                ContentUnavailableView {
                    Label {
                        Text("No Transaction", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc")
                    }
                } description: {
                    Text("Paste or open a transaction on the Overview first.", bundle: #bundle)
                }
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label {
                        Text("The Transaction Did Not Decode", bundle: #bundle)
                    } icon: {
                        Image(systemName: "xmark.octagon")
                    }
                } description: {
                    Text(verbatim: message)
                }
            case .loaded(let inspection):
                content(inspection)
            }
        }
        .navigationTitle(Text(title))
    }
}
