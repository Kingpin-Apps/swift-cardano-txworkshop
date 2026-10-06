import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// One section of a document, under a toolbar that is the same on every
/// section: the network, and what works on the whole transaction (export and
/// share, compare, replace). A section adds its own buttons beside them.
struct SectionDetail: View {
    let section: WorkshopSection
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>
    @Environment(\.undoManager) private var undoManager
    @State private var isComparing = false
    @State private var isReplacing = false

    var body: some View {
        content
            .environment(\.documentNetwork, document.content.network)
            .twScreenBackground()
            #if os(iOS)
            // A document's sections are pages of one window, not places to
            // arrive at: small titles, as in other document apps.
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    NetworkToolbarMenu(document: document)
                }
                if let transaction = document.content.transaction {
                    ToolbarItem {
                        ExportShareMenu(document: document, transaction: transaction, inspection: inspection.value)
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
                    // Replacing the transaction sits apart from the actions
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

    @ViewBuilder private var content: some View {
        switch section {
        case .overview:
            OverviewView(document: document, inspection: inspection)
        case .inputsOutputs:
            InputsOutputsView(document: document, inspection: inspection)
        case .body:
            BodyView(inspection: inspection)
        case .scripts:
            ScriptsView(document: document, inspection: inspection)
        case .metadata:
            MetadataView(inspection: inspection)
        case .sign:
            SignView(document: document)
        case .build:
            BuildView(document: document)
        case .chainData:
            ChainDataView(document: document)
        case .validate:
            ValidateView(document: document)
        case .cddl:
            CDDLWorkspaceView(
                document: document,
                defaultEra: SchemaCheck.defaultEra(possibleEras: inspection.value?.summary.possibleEras ?? "")
            )
        case .cbor:
            CBORExplorerView(
                document: document,
                defaultEra: SchemaCheck.defaultEra(possibleEras: inspection.value?.summary.possibleEras ?? "")
            )
        }
    }
}
