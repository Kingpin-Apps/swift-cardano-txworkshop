import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The summary of a decoded transaction, with its notes.
struct TransactionOverview: View {
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>
    @State private var isComparing = false
    @State private var isReplacing = false
    @Environment(\.undoManager) private var undoManager

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
            if let transaction = document.content.transaction {
                ToolbarItem {
                    ExportShareMenu(document: document, transaction: transaction, inspection: inspection.value)
                }
            }
            if inspection.value != nil {
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
            // Replacing the loaded transaction sits apart from the actions
            // that work on it.
            ToolbarItem(placement: .navigation) {
                Button {
                    isReplacing = true
                } label: {
                    Label {
                        Text("Replace Transaction…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .help(Text("Replace this transaction: paste one, open a file, or fetch one by its ID", bundle: #bundle))
                .accessibilityIdentifier("replaceTransaction")
            }
        }
        .sheet(isPresented: $isReplacing) {
            ReplaceTransactionSheet(document: document, undoManager: undoManager)
        }
        .sheet(isPresented: $isComparing) {
            if let current = inspection.value {
                CompareSheet(document: document, current: current)
            }
        }
    }
}
