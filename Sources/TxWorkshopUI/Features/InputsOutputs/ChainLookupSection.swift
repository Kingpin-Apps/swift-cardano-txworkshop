import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Looks the inputs and token names up, and keeps what it finds in the
/// document so it can be read offline.
struct ChainLookupSection: View {
    let document: TxWorkshopDocument
    let inspection: TransactionInspection
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.undoManager) private var undoManager
    @State private var isLookingUp = false
    @State private var problem: AttributedString?

    private var network: CardanoNetwork? { document.content.network }
    private var provider: ProviderConfiguration? { network.flatMap { providers.selectedProvider(for: $0) } }
    private var snapshot: ChainContextSnapshot? { document.content.chainContext }

    var body: some View {
        Section {
            if let snapshot {
                TWFieldRow(LocalizedStringResource("Looked up", bundle: #bundle)) {
                    Text(snapshot.fetchedAt, format: .relative(presentation: .named))
                }
            }
            if let problem {
                Label {
                    Text(problem)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .labelStyle(.status(TWColor.failure))
            }
            Button(action: lookUp) {
                Group {
                    if snapshot == nil {
                        Text("Look Up Inputs & Names", bundle: #bundle)
                    } else {
                        Text("Look Up Again", bundle: #bundle)
                    }
                }
                .opacity(isLookingUp ? 0 : 1)
                .overlay { if isLookingUp { ProgressView() } }
            }
            .disabled(isLookingUp || network == nil)
        } header: {
            Text("Chain Data", bundle: #bundle)
        } footer: {
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if let network {
            if let provider {
                Text("Asks \(provider.name) for the outputs the inputs spend, and the \(Text(network.name)) token registry for asset names. What it finds is saved in the document.", bundle: #bundle)
            } else {
                Text("Add a provider for \(Text(network.name)) in Settings to look inputs up. Asset names come from the token registry.", bundle: #bundle)
            }
        } else {
            Text("Set the network in Overview to look inputs up.", bundle: #bundle)
        }
    }

    private func lookUp() {
        guard let network, let transaction = document.content.transaction else { return }
        let source = provider.map { TransactionFetcher.Source(provider: $0, apiKey: providers.apiKey(for: $0)) }
        let assets = inspection.outputs.flatMap(\.assets) + inspection.mint
            + (inspection.inputs + inspection.referenceInputs).compactMap(\.output).flatMap(\.assets)
        isLookingUp = true
        problem = nil
        Task {
            defer { isLookingUp = false }
            async let tokens = try? TokenRegistryLookup().lookup(assets, network: network)
            var resolved: ResolvedInputs?
            if let source {
                do {
                    resolved = try await InputResolver().resolve(transaction: transaction, provider: source.provider, apiKey: source.apiKey)
                } catch {
                    problem = AttributedString(String(describing: error))
                }
            }
            let names = await tokens
            guard resolved != nil || names != nil else {
                if problem == nil {
                    problem = AttributedString(localized: "The token registry could not be reached.", bundle: #bundle)
                }
                return
            }
            if let missing = resolved?.missing, !missing.isEmpty {
                problem = AttributedString(localized: "^[\(missing.count) input](inflect: true) not found.", bundle: #bundle)
            }
            let previous = snapshot
            document.update({ content in
                content.chainContext = ChainContextSnapshot(
                    fetchedAt: .now,
                    utxos: resolved?.utxos ?? previous?.utxos ?? [],
                    spentInputs: resolved?.spent ?? previous?.spentInputs,
                    tokens: names ?? previous?.tokens,
                    protocolParameters: previous?.protocolParameters,
                    tipSlot: previous?.tipSlot
                )
            }, actionName: LocalizedStringResource("Look Up Chain Data", bundle: #bundle), undoManager: undoManager)
        }
    }
}
