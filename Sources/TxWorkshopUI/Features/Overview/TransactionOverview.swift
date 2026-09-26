import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The summary of a decoded transaction, with its notes.
struct TransactionOverview: View {
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>
    @State private var isComparing = false

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
                    .foregroundStyle(TWColor.failure)
                }
            case .loaded(let inspection):
                Section {
                    Text(verbatim: TransactionDescription.sentence(for: inspection))
                } header: {
                    Text("In short", bundle: #bundle)
                }
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
                }
            }
            if let envelope = envelopeText {
                ToolbarItem {
                    ShareLink(item: envelope, preview: SharePreview(Text("Transaction", bundle: #bundle))) {
                        Label {
                            Text("Share Transaction", bundle: #bundle)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isComparing) {
            if let current = inspection.value {
                CompareSheet(document: document, current: current)
            }
        }
    }

    /// The transaction as a cardano-cli text envelope, for sharing.
    private var envelopeText: String? {
        (try? TxDocumentCodec.file(for: document.content, format: .textEnvelope)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
