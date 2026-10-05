import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Fetches a document's chain data from its network's provider: everything
/// its transaction needs, or, without a transaction, the chain alone.
@MainActor
enum ChainDataFetch {
    enum FetchError: Error, CustomStringConvertible {
        case noNetwork
        case noProvider(CardanoNetwork)

        var description: String {
            switch self {
            case .noNetwork: String(localized: "Set the document's network first.", bundle: #bundle)
            case .noProvider(let network):
                String(localized: "Add a provider for \(String(localized: network.name)) in Settings first.", bundle: #bundle)
            }
        }
    }

    /// The provider a fetch would use, if there is one.
    static func provider(for document: TxWorkshopDocument, in providers: ProviderSettingsStore) -> ProviderConfiguration? {
        document.content.network.flatMap { providers.selectedProvider(for: $0) }
    }

    static func run(document: TxWorkshopDocument, providers: ProviderSettingsStore, undoManager: UndoManager?) async throws {
        guard let network = document.content.network else { throw FetchError.noNetwork }
        guard let provider = providers.selectedProvider(for: network) else { throw FetchError.noProvider(network) }
        let apiKey = providers.apiKey(for: provider)
        let previous = document.content.chainContext
        let snapshot = if let bytes = document.content.transaction {
            try await ChainDataFetcher().fetch(transaction: bytes, provider: provider, apiKey: apiKey, keeping: previous)
        } else {
            try await ChainDataFetcher().fetchChain(provider: provider, apiKey: apiKey, keeping: previous)
        }
        document.update(
            { $0.chainContext = snapshot },
            actionName: LocalizedStringResource("Fetch Chain Data", bundle: #bundle),
            undoManager: undoManager
        )
    }
}
