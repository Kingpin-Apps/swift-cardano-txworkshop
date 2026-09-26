import SwiftUI
import TxWorkshopCore

struct SectionDetail: View {
    let section: WorkshopSection
    let document: TxWorkshopDocument

    var body: some View {
        switch section {
        case .overview:
            OverviewView(document: document)
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
