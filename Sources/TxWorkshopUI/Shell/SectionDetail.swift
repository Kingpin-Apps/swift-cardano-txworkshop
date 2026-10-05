import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

struct SectionDetail: View {
    let section: WorkshopSection
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>

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
