import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The summary of a decoded transaction, with its notes.
struct TransactionOverview: View {
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>

    var body: some View {
        Form {
            switch inspection {
            case .idle, .loading:
                Section { ProgressView() }
            case .failed(let message):
                Section {
                    Label {
                        Text("This transaction did not decode: \(message)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "xmark.octagon")
                    }
                    .labelStyle(.status(TWColor.failure))
                }
            case .loaded(let inspection):
                InShortSection(inspection: inspection)
                Section {
                    SummaryRows(summary: inspection.summary)
                } header: {
                    Text("Transaction", bundle: #bundle)
                }
                ValiditySection(validity: inspection.validity)
            }
            NetworkSection(document: document)
            NotesSection(document: document)
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Overview", bundle: #bundle))
    }
}
