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
    /// What the last build spent, kept while the next one runs.
    @State private var lastSpent: [TransactionComposer.SpentInput] = []
    @State private var usesProvider = true
    @State private var networkHints = BuildNetworkHints()
    /// What is wrong with the recipe, shown after Build is pressed and kept
    /// up to date as it is fixed.
    @State private var problems: [RecipeProblem] = []
    @State private var checksRecipe = false

    init(document: TxWorkshopDocument) {
        self.document = document
        // No output to start with: a transaction may only register or
        // delegate, with what is left going back as change.
        recipe = document.content.recipe ?? BuildRecipe()
    }

    private var provider: ProviderConfiguration? {
        document.content.network.flatMap { providers.selectedProvider(for: $0) }
    }

    var body: some View {
        Form {
            // The network is chosen in the toolbar; here it only speaks up
            // when the addresses point elsewhere.
            if let hint = recipeHint, !hint.fits(document.content.network) {
                Section {
                    NetworkSuggestion(document: document, hint: hint, source: Text("The addresses here", bundle: #bundle))
                }
            }
            SourcesSection(recipe: $recipe, provider: provider, spent: lastSpent)
            ForEach($recipe.outputs) { $output in
                OutputDraftSection(output: $output, blueprints: $recipe.blueprints, applied: BlueprintCatalog.appliedScripts(in: recipe)) {
                    recipe.outputs.removeAll { $0.id == output.id }
                }
            }
            ForEach($recipe.mints) { $mint in
                MintDraftSection(mint: $mint, blueprints: $recipe.blueprints, applied: BlueprintCatalog.appliedScripts(in: recipe)) {
                    recipe.mints.removeAll { $0.id == mint.id }
                }
            }
            ForEach($recipe.scriptInputs) { $input in
                ScriptInputSection(input: $input, blueprints: $recipe.blueprints, applied: BlueprintCatalog.appliedScripts(in: recipe)) {
                    recipe.scriptInputs.removeAll { $0.id == input.id }
                }
            }
            ForEach($recipe.certificates) { $item in
                CertificateDraftSection(item: $item) {
                    recipe.certificates.removeAll { $0.id == item.id }
                }
            }
            ForEach($recipe.withdrawals) { $withdrawal in
                WithdrawalDraftSection(withdrawal: $withdrawal) {
                    recipe.withdrawals.removeAll { $0.id == withdrawal.id }
                }
            }
            ForEach($recipe.votes) { $vote in
                VoteDraftSection(vote: $vote) {
                    recipe.votes.removeAll { $0.id == vote.id }
                }
            }
            ForEach($recipe.proposals) { $proposal in
                ProposalDraftSection(proposal: $proposal) {
                    recipe.proposals.removeAll { $0.id == proposal.id }
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
                Button {
                    recipe.mints.append(MintDraft(assets: [AssetDraft()]))
                } label: {
                    Label {
                        Text("Add Mint or Burn", bundle: #bundle)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }
                Button {
                    recipe.scriptInputs.append(ScriptInputDraft())
                } label: {
                    Label {
                        Text("Add Script Input", bundle: #bundle)
                    } icon: {
                        Image(systemName: "lock.open")
                    }
                }
                Menu {
                    Button {
                        recipe.certificates.append(CertificateItem(certificate: .registerStake(stakeAddress: "")))
                    } label: { Text("Certificate", bundle: #bundle) }
                    Button {
                        recipe.withdrawals.append(WithdrawalDraft())
                    } label: { Text("Withdrawal", bundle: #bundle) }
                    Button {
                        recipe.votes.append(VoteDraft())
                    } label: { Text("Vote", bundle: #bundle) }
                    Button {
                        recipe.proposals.append(ProposalDraft())
                    } label: { Text("Proposal", bundle: #bundle) }
                } label: {
                    Label {
                        Text("Add Staking or Governance", bundle: #bundle)
                    } icon: {
                        Image(systemName: "building.columns")
                    }
                }
                TextField(value: $recipe.donation, format: .number) {
                    Text("Treasury donation (lovelace)", bundle: #bundle)
                }
                .font(TWFont.figure)
            }
            BuildOptionsSection(recipe: $recipe)
            DocumentBlueprintsSection(recipe: $recipe)
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
                .accessibilityIdentifier("buildRecipe")
            } footer: {
                if document.content.network == nil {
                    Text("Set the network in Overview first.", bundle: #bundle)
                } else {
                    Text("Protocol parameters come from the document's chain data, or the provider. Without a provider, only pasted UTxOs are spent.", bundle: #bundle)
                }
            }
            if !problems.isEmpty {
                Section {
                    ForEach(problems) { problem in
                        Label {
                            VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                                Text(verbatim: "\(problem.place) · \(problem.field)").font(.subheadline.weight(.semibold))
                                Text(verbatim: problem.message)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .labelStyle(.status(TWColor.failure))
                    }
                } header: {
                    Text("Fix before building", bundle: #bundle)
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
                    .labelStyle(.status(TWColor.failure))
                }
            case .loaded(let built):
                CompositionSections(composition: built, onUse: { use(built) })
            }
        }
        .formStyle(.grouped)
        .environment(\.documentNetwork, document.content.network)
        .environment(networkHints)
        .onChange(of: recipeHint, initial: true) { _, hint in
            // An unknown network is taken from the addresses when they say
            // which one it is.
            if document.content.network == nil, case .network(let network)? = hint {
                document.setNetwork(network, undoManager: undoManager)
            }
        }
        .onChange(of: recipe) {
            if checksRecipe { problems = RecipeCheck.problems(recipe, network: document.content.network) }
        }
        // Choosing which UTxOs to spend builds again at once, so the result
        // shown is always for the inputs chosen.
        .onChange(of: [recipe.fixedInputs, recipe.excludedInputs]) {
            switch composition {
            case .loaded, .failed: build()
            case .idle, .loading: break
            }
        }
        .navigationTitle(Text("Build", bundle: #bundle))
    }

    /// What the recipe's addresses say about its network.
    private var recipeHint: NetworkHint? {
        let values: [(ValueKind, String)] =
            recipe.outputs.map { (.address, $0.address) } + recipe.sourceAddresses.map { (.address, $0) }
            + [(.address, recipe.changeAddress)]
            + recipe.withdrawals.map { (.stakeAddress, $0.stakeAddress) }
            + recipe.proposals.map { (.stakeAddress, $0.returnAddress) }
        let hints = values.compactMap { NetworkGuess.hint(for: $0.0, text: $0.1) }
        if hints.contains(.network(.mainnet)) {
            return hints.allSatisfy { $0 == .network(.mainnet) } ? .network(.mainnet) : nil
        }
        guard !hints.isEmpty else { return nil }
        return networkHints.fromFileName.map { .network($0) } ?? .testnet
    }

    private func build() {
        let recipe = recipe
        let snapshot = document.content.chainContext
        let network = document.content.network
        let provider = usesProvider ? provider : nil
        let apiKey = provider.flatMap { providers.apiKey(for: $0) }
        checksRecipe = true
        problems = RecipeCheck.problems(recipe, network: network)
        guard problems.isEmpty else {
            composition = .idle
            return
        }
        composition = .loading
        document.update({ $0.recipe = recipe }, actionName: LocalizedStringResource("Edit Recipe", bundle: #bundle), undoManager: undoManager)
        Task {
            do {
                let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: network, provider: provider, apiKey: apiKey)
                composition = .loaded(built)
                lastSpent = built.spent
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
