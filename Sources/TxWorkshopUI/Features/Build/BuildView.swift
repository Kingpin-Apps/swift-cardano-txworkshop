import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A form for a transaction, built with swift-cardano-txbuilder: coin
/// selection, change, min-ADA and the fee. The recipe is kept in the
/// document; the built transaction replaces the document's when asked.
struct BuildView: View {
    let document: TxWorkshopDocument
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(WorkshopSession.self) private var session
    @Environment(\.undoManager) private var undoManager
    @State private var recipe: BuildRecipe
    @State private var composition: LoadState<TransactionComposer.Composition> = .idle
    @State private var usesProvider = true

    init(document: TxWorkshopDocument) {
        self.document = document
        recipe = document.content.recipe ?? BuildRecipe(outputs: [OutputDraft()])
    }

    private var provider: ProviderConfiguration? {
        document.content.network.flatMap { providers.selectedProvider(for: $0) }
    }

    var body: some View {
        Form {
            SourcesSection(recipe: $recipe, provider: provider)
            ForEach($recipe.outputs) { $output in
                OutputDraftSection(output: $output) {
                    recipe.outputs.removeAll { $0.id == output.id }
                }
            }
            Section {
                Button {
                    recipe.outputs.append(OutputDraft())
                } label: {
                    Label {
                        Text("Add Output", bundle: #bundle)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
            BuildOptionsSection(recipe: $recipe)
            Section {
                if provider != nil {
                    Toggle(isOn: $usesProvider) {
                        Text("Use the provider for address UTxOs and the tip", bundle: #bundle)
                    }
                }
                Button(action: build) {
                    Text("Build", bundle: #bundle)
                        .opacity(composition.isLoading ? 0 : 1)
                        .overlay { if composition.isLoading { ProgressView() } }
                }
                .disabled(composition.isLoading || document.content.network == nil)
            } footer: {
                if document.content.network == nil {
                    Text("Set the network in Overview first.", bundle: #bundle)
                } else {
                    Text("Protocol parameters come from the document's chain data, or the provider. Without a provider, only pasted UTxOs are spent.", bundle: #bundle)
                }
            }
            switch composition {
            case .idle, .loading:
                EmptyView()
            case .failed(let message):
                Section {
                    Label {
                        Text(verbatim: message)
                    } icon: {
                        Image(systemName: "xmark.octagon")
                    }
                    .foregroundStyle(TWColor.failure)
                }
            case .loaded(let built):
                CompositionSections(composition: built, onUse: { use(built) })
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Build", bundle: #bundle))
    }

    private func build() {
        let recipe = recipe
        let snapshot = document.content.chainContext
        let network = document.content.network
        let provider = usesProvider ? provider : nil
        let apiKey = provider.flatMap { providers.apiKey(for: $0) }
        composition = .loading
        document.update({ $0.recipe = recipe }, actionName: LocalizedStringResource("Edit Recipe", bundle: #bundle), undoManager: undoManager)
        Task {
            do {
                composition = .loaded(try await TransactionComposer().compose(recipe, snapshot: snapshot, network: network, provider: provider, apiKey: apiKey))
            } catch {
                composition = .failed(String(describing: error))
            }
        }
    }

    /// Makes the built transaction the document's, to inspect, validate and
    /// sign.
    private func use(_ built: TransactionComposer.Composition) {
        document.update({ content in
            content.transaction = built.transaction
            content.envelope = nil
        }, actionName: LocalizedStringResource("Use Built Transaction", bundle: #bundle), undoManager: undoManager)
        session.selection = .overview
    }
}
