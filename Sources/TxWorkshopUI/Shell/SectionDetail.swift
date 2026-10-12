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
    @Environment(WorkshopSession.self) private var session
    @State private var isComparing = false
    @State private var isReplacing = false
    /// The form read from the transaction, waiting to replace the one there.
    @State private var pendingEdit: RecipeImporter.Result?
    @State private var editProblem: String?
    /// Whether the problem is UTxOs the chain data lacks.
    @State private var editNeedsChainData = false

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
                    ToolbarItem {
                        Button(action: editInBuild) {
                            Label {
                                Text("Edit in Build…", bundle: #bundle)
                            } icon: {
                                Image(systemName: "slider.horizontal.3")
                            }
                        }
                        .help(Text("Change this transaction in Build, where it is built again: the fee, change and script budgets are worked out anew", bundle: #bundle))
                        .accessibilityIdentifier("editInBuild")
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
            .confirmationDialog(
                String(localized: "Replace the Build form?", bundle: #bundle),
                isPresented: Binding { pendingEdit != nil } set: { if !$0 { pendingEdit = nil } }
            ) {
                Button(role: .destructive) {
                    if let pendingEdit { open(pendingEdit) }
                } label: {
                    Text("Replace", bundle: #bundle)
                }
            } message: {
                Text("Build already has a form. It is replaced by this transaction's; Undo brings it back.", bundle: #bundle)
            }
            .alert(
                String(localized: "This transaction cannot be edited in Build", bundle: #bundle),
                isPresented: Binding { editProblem != nil } set: { if !$0 { editProblem = nil } }
            ) {
                if editNeedsChainData {
                    Button {
                        session.selection = .chainData
                    } label: {
                        Text("Open Chain Data", bundle: #bundle)
                    }
                }
                Button(role: .cancel) {} label: { Text("OK", bundle: #bundle) }
            } message: {
                Text(verbatim: editProblem ?? "")
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

    /// Reads the transaction into the Build form, asking first when that
    /// would replace a different form.
    private func editInBuild() {
        guard let bytes = document.content.transaction else { return }
        do {
            let result = try RecipeImporter.recipe(
                from: bytes, snapshot: document.content.chainContext, network: document.content.network,
                keeping: document.content.recipe?.blueprints ?? []
            )
            if let current = document.content.recipe, current != BuildRecipe(), current != result.recipe {
                pendingEdit = result
            } else {
                open(result)
            }
        } catch {
            if case .missingInputs? = error as? ImportError { editNeedsChainData = true } else { editNeedsChainData = false }
            editProblem = String(describing: error)
        }
    }

    private func open(_ result: RecipeImporter.Result) {
        document.update(
            { $0.recipe = result.recipe }, actionName: LocalizedStringResource("Edit in Build", bundle: #bundle), undoManager: undoManager
        )
        session.importNotes = result.notes
        session.selection = .build
        pendingEdit = nil
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
