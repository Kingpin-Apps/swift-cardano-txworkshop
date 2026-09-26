import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

struct SectionDetail: View {
    let section: WorkshopSection
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>

    var body: some View {
        switch section {
        case .overview:
            OverviewView(document: document, inspection: inspection)
        case .inputsOutputs:
            InputsOutputsView(inspection: inspection)
        case .body:
            BodyView(inspection: inspection)
        case .scripts:
            ScriptsView(inspection: inspection)
        case .metadata:
            MetadataView(inspection: inspection)
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
