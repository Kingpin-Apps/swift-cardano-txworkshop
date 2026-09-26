import SwiftUI

struct SectionLink: View {
    let section: WorkshopSection

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.systemImage)
        }
        .tag(section)
    }
}
