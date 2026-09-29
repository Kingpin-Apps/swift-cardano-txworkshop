import SwiftCardanoExplorers
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The block explorer that links open in.
struct ExplorerSection: View {
    @AppStorage(BlockchainExplorer.storageKey) private var explorer = BlockchainExplorer.cexplorer

    var body: some View {
        Section {
            Picker(selection: $explorer) {
                ForEach(BlockchainExplorer.allCases) { explorer in
                    Text(verbatim: explorer.name).tag(explorer)
                }
            } label: {
                Text("Explorer", bundle: #bundle)
            }
        } header: {
            #if !os(macOS)
            Text("Block Explorer", bundle: #bundle)
            #endif
        } footer: {
            VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                Text(verbatim: explorer.summary)
                Text("Covers \(networks). Where it has no page for something, another explorer that does is used.", bundle: #bundle)
            }
        }
    }

    /// The networks the explorer covers, by the names the app uses.
    private var networks: String {
        [CardanoNetwork.mainnet, .preprod, .preview]
            .filter { explorer.supports($0.cardanoCoreNetwork) }
            .map { String(localized: $0.name) }
            .formatted(.list(type: .and))
    }
}
