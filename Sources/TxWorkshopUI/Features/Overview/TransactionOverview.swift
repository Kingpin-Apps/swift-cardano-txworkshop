import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The summary of a decoded transaction.
struct TransactionOverview: View {
    let document: TxWorkshopDocument
    let transaction: Data
    @State private var summary: LoadState<TransactionSummary> = .idle

    var body: some View {
        Form {
            Section {
                switch summary {
                case .idle, .loading:
                    ProgressView()
                case .failed(let message):
                    Label {
                        Text("This transaction did not decode: \(message)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "xmark.octagon")
                    }
                    .foregroundStyle(TWColor.failure)
                case .loaded(let summary):
                    SummaryRows(summary: summary)
                }
            } header: {
                Text("Transaction", bundle: #bundle)
            }
            NotesSection(document: document)
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Overview", bundle: #bundle))
        .task(id: transaction) {
            summary = .loading
            do {
                summary = .loaded(try await TransactionInspector().inspect(transaction))
            } catch {
                summary = .failed(String(describing: error))
            }
        }
    }
}
