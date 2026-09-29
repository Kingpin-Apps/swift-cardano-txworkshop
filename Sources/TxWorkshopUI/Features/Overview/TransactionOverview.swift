import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The summary of a decoded transaction, with its notes.
struct TransactionOverview: View {
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>
    @State private var isComparing = false
    @State private var isFetching = false

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
        .toolbar {
            if let current = inspection.value {
                ToolbarItem {
                    ExportMenu(document: document, inspection: current)
                }
                ToolbarItem {
                    Button {
                        isComparing = true
                    } label: {
                        Label {
                            Text("Compare With…", bundle: #bundle)
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right.square")
                        }
                    }
                    .help(Text("Compare this transaction with another", bundle: #bundle))
                }
            }
            // Fetching replaces the loaded transaction, so it sits apart from
            // the actions that work on it.
            ToolbarItem(placement: .navigation) {
                Button {
                    isFetching = true
                } label: {
                    Label {
                        Text("Fetch by ID…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .help(Text("Replace this transaction with one fetched by its ID", bundle: #bundle))
            }
            if let transaction = document.content.transaction {
                ToolbarItem {
                    ShareTransactionLink(transaction: transaction, envelope: document.content.envelope)
                }
            }
        }
        .sheet(isPresented: $isFetching) {
            FetchByHashSheet(document: document)
        }
        .sheet(isPresented: $isComparing) {
            if let current = inspection.value {
                CompareSheet(document: document, current: current)
            }
        }
    }
}
