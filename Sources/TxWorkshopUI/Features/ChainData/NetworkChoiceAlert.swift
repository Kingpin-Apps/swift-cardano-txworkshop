import SwiftUI
import TxWorkshopCore

extension View {
    /// Asks for the document's network when the view appears and it has
    /// none, offering the networks with a provider first.
    func networkChoiceAlert(for document: TxWorkshopDocument) -> some View {
        modifier(NetworkChoiceAlert(document: document))
    }
}

private struct NetworkChoiceAlert: ViewModifier {
    let document: TxWorkshopDocument
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.undoManager) private var undoManager
    @State private var isPresented = false

    /// Every network to offer, with the provider it would fetch from: the
    /// public networks, and any custom one a provider is set up for.
    private var choices: [(network: CardanoNetwork, provider: ProviderConfiguration?)] {
        var networks = CardanoNetwork.allCases
        for provider in providers.settings.providers where !networks.contains(provider.network) {
            networks.append(provider.network)
        }
        let all = networks.map { ($0, providers.selectedProvider(for: $0)) }
        return all.filter { $0.1 != nil } + all.filter { $0.1 == nil }
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if document.content.network == nil { isPresented = true }
            }
            .alert(String(localized: "Choose a network", bundle: #bundle), isPresented: $isPresented) {
                ForEach(choices, id: \.network) { choice in
                    Button {
                        document.setNetwork(choice.network, undoManager: undoManager)
                    } label: {
                        if let provider = choice.provider {
                            Text("\(Text(choice.network.name)) · \(provider.name)", bundle: #bundle)
                        } else {
                            Text(choice.network.name)
                        }
                    }
                }
                Button(role: .cancel) {} label: { Text("Not Now", bundle: #bundle) }
            } message: {
                if choices.contains(where: { $0.provider != nil }) {
                    Text("Chain data is fetched from the network's provider. Networks with a provider are listed first, with its name.", bundle: #bundle)
                } else {
                    Text("Chain data is fetched from the network's provider. None is set up yet: add one in Settings, such as Koios, which needs no sign-up.", bundle: #bundle)
                }
            }
    }
}
