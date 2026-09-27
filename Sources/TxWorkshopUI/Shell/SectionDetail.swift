import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

struct SectionDetail: View {
    let section: WorkshopSection
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>

    var body: some View {
        content
            .twScreenBackground()
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
            ScriptsView(inspection: inspection)
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
        default:
            ContentUnavailableView {
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.systemImage)
                }
            } description: {
                if let phase = section.comingInPhase {
                    Text("Arrives in phase \(phase) of the build.", bundle: #bundle)
                }
            }
        }
    }
}
