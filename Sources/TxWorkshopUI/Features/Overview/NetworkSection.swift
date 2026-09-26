import SwiftUI
import TxWorkshopCore

/// The network the document's transaction is for.
struct NetworkSection: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager
    @State private var network: CardanoNetwork?

    var body: some View {
        Section {
            Picker(selection: $network) {
                Text("Unknown", bundle: #bundle).tag(CardanoNetwork?.none)
                ForEach(CardanoNetwork.allCases) { network in
                    Text(network.name).tag(Optional(network))
                }
            } label: {
                Text("Network", bundle: #bundle)
            }
        } footer: {
            Text("Places the validity window in time, and picks the provider used for this transaction.", bundle: #bundle)
        }
        .onAppear { network = document.content.network }
        .onChange(of: network) { _, newValue in
            guard newValue != document.content.network else { return }
            document.update(
                { $0.network = newValue },
                actionName: LocalizedStringResource("Change Network", bundle: #bundle),
                undoManager: undoManager
            )
        }
        .onChange(of: document.content.network) { _, newValue in
            if newValue != network { network = newValue }
        }
    }
}
