import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The transaction's metadata, label by label.
struct MetadataView: View {
    let inspection: LoadState<TransactionInspection>

    var body: some View {
        InspectionContainer(inspection: inspection, title: LocalizedStringResource("Metadata", bundle: #bundle)) { inspection in
            if inspection.metadata.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Metadata", bundle: #bundle)
                    } icon: {
                        Image(systemName: "tag")
                    }
                } description: {
                    Text("This transaction carries no metadata.", bundle: #bundle)
                }
            } else {
                Form {
                    ForEach(inspection.metadata) { entry in
                        Section {
                            if let message = entry.message {
                                Text(verbatim: message)
                                    .textSelection(.enabled)
                            }
                            DataTreeView(node: entry.tree)
                        } header: {
                            if let registeredAs = entry.registeredAs {
                                Text("Label \(entry.label) · \(registeredAs)", bundle: #bundle)
                            } else {
                                Text("Label \(entry.label)", bundle: #bundle)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}
