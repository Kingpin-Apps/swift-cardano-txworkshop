import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Where the builder may take funds from: watch-only addresses, and UTxOs
/// pasted or fetched from them, each spent when coin selection picks it,
/// always, or never.
struct SourcesSection: View {
    @Binding var recipe: BuildRecipe
    let provider: ProviderConfiguration?
    /// The document whose chain data is fetched alongside the UTxOs.
    let document: TxWorkshopDocument
    /// What the last build spent, so an input it picked can be left out even
    /// when it was not fetched here.
    var spent: [TransactionComposer.SpentInput] = []
    @Environment(ProviderSettingsStore.self) private var providers
    @State private var isFetching = false
    @State private var problem: String?
    @State private var chainProblem: String?
    /// The addresses last fetched from, or there when the form opened, so
    /// only an address the user adds starts a fetch on its own.
    @State private var fetchedAddresses: [String]?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Section {
            ValueLinesEditor(kind: .address, lines: $recipe.sourceAddresses, label: Text("Source addresses, one per line", bundle: #bundle))
            Button(action: fetch) {
                Text("Fetch UTxOs", bundle: #bundle)
                    .opacity(isFetching ? 0 : 1)
                    .overlay { if isFetching { ProgressView() } }
            }
            .disabled(isFetching || provider == nil || recipe.sourceAddresses.isEmpty)
            if let problem {
                TWErrorText(problem)
            }
            if let chainProblem {
                TWErrorText(chainProblem)
            }
        } header: {
            Text("Source addresses", bundle: #bundle)
        } footer: {
            Text("One per line: bech32, hex, or read from .addr or payment key files. Adding an address fetches its UTxOs on its own, and the chain data too when there is none yet or the epoch has turned since. Fetching replaces the UTxOs listed with theirs, and saves them in the recipe, so it builds offline later.", bundle: #bundle)
        }
        .onAppear {
            if fetchedAddresses == nil { fetchedAddresses = recipe.sourceAddresses }
        }
        // A pause after the last change, so a fetch never starts on an
        // address still being typed or pasted line by line.
        .task(id: recipe.sourceAddresses) {
            let addresses = recipe.sourceAddresses
            guard let fetchedAddresses, addresses != fetchedAddresses, provider != nil,
                  TransactionComposer.areAddresses(addresses) else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, !isFetching else { return }
            fetch()
        }
        Section {
            if recipe.utxos.isEmpty && otherInputs.isEmpty {
                Text("None yet. Fetch the source addresses' UTxOs above.", bundle: #bundle)
                    .foregroundStyle(TWColor.secondaryText)
            }
            ForEach(recipe.utxos, id: \.self) { hex in
                if let described = TransactionComposer.describe(utxoHex: hex) {
                    UTxOChoiceRow(
                        id: described.id, lovelace: described.lovelace, assetCount: described.assetCount,
                        tokens: TransactionComposer.tokens(utxoHex: hex),
                        isSpent: spentIDs.contains(described.id), choice: choice(for: described.id)
                    )
                } else {
                    Label {
                        Text("Not a UTxO: \(String(hex.prefix(16)))…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .labelStyle(.status(TWColor.warning))
                }
            }
            // Inputs the last build took from the provider, or chosen before
            // and no longer listed above.
            ForEach(otherInputs) { input in
                UTxOChoiceRow(
                    id: input.id, lovelace: input.lovelace, assetCount: input.assetCount, tokens: [],
                    isSpent: spentIDs.contains(input.id), choice: choice(for: input.id)
                )
            }
        } header: {
            Text("UTxOs to spend", bundle: #bundle)
        } footer: {
            Text("Coin selection picks from them automatically; choose Always Use or Don't Use to decide yourself, for example to leave out a UTxO another transaction still being signed spends.", bundle: #bundle)
        }
    }

    private var spentIDs: Set<String> { Set(spent.map(\.id)) }

    /// Inputs not among the listed UTxOs: spent by the last build, or chosen.
    private var otherInputs: [TransactionComposer.SpentInput] {
        let listed = Set(recipe.utxos.compactMap { TransactionComposer.describe(utxoHex: $0)?.id })
        var others = spent.filter { !listed.contains($0.id) }
        for id in recipe.fixedInputs + recipe.excludedInputs where !listed.contains(id) && !others.contains(where: { $0.id == id }) {
            others.append(TransactionComposer.SpentInput(id: id, lovelace: 0, assetCount: 0))
        }
        return others
    }

    private func choice(for id: String) -> Binding<BuildRecipe.InputChoice> {
        Binding { recipe.choice(for: id) } set: { recipe.setChoice($0, for: id) }
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Puts the fetched UTxOs in place of those listed: a listed UTxO the
    /// addresses no longer hold is spent, and building with it would make a
    /// transaction the chain rejects. Choices for UTxOs that were listed and
    /// are gone go with them.
    static func replaceUTxOs(in recipe: inout BuildRecipe, with found: [String]) {
        let ids = { (hexes: [String]) in Set(hexes.compactMap { TransactionComposer.describe(utxoHex: $0)?.id }) }
        let gone = ids(recipe.utxos).subtracting(ids(found))
        recipe.utxos = found
        recipe.fixedInputs.removeAll { gone.contains($0) }
        recipe.excludedInputs.removeAll { gone.contains($0) }
    }

    /// Fetches the addresses' UTxOs and, beside them, the chain data, so the
    /// tip and protocol parameters are there without a trip to Chain Data.
    private func fetch() {
        guard let provider else { return }
        let addresses = recipe.sourceAddresses
        let apiKey = providers.apiKey(for: provider)
        isFetching = true
        problem = nil
        chainProblem = nil
        fetchedAddresses = addresses
        // Chain data is kept until the epoch turns, or the user fetches it in
        // Chain Data; most fetches here need only the UTxOs.
        let needsChain = ChainDataFreshness.needsFetch(document.content.chainContext, network: document.content.network)
        Task {
            defer { isFetching = false }
            async let chain: Void = needsChain
                ? ChainDataFetch.run(document: document, providers: providers, undoManager: undoManager)
                : ()
            do {
                let found = try await TransactionComposer().utxos(at: addresses, provider: provider, apiKey: apiKey)
                Self.replaceUTxOs(in: &recipe, with: found)
            } catch {
                problem = String(describing: error)
            }
            do {
                try await chain
            } catch {
                chainProblem = String(localized: "The chain data could not be fetched: \(String(describing: error))", bundle: #bundle)
            }
        }
    }
}

/// One UTxO, what it holds, whether the last build spent it, and how coin
/// selection should treat it.
private struct UTxOChoiceRow: View {
    let id: String
    let lovelace: UInt64
    let assetCount: Int
    let tokens: [TransactionComposer.HeldToken]
    let isSpent: Bool
    @Binding var choice: BuildRecipe.InputChoice

    var body: some View {
        Picker(selection: $choice) {
            Text("Automatic", bundle: #bundle).tag(BuildRecipe.InputChoice.automatic)
            Text("Always Use", bundle: #bundle).tag(BuildRecipe.InputChoice.always)
            Text("Don't Use", bundle: #bundle).tag(BuildRecipe.InputChoice.never)
        } label: {
            VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                TWBytesText(id, font: TWFont.bytesSmall)
                HStack(spacing: TWSpacing.s) {
                    if lovelace > 0 {
                        Text(verbatim: TWFormat.ada(lovelace)).font(TWFont.figure)
                    }
                    if assetCount > 0 {
                        TokensButton(count: assetCount, tokens: tokens)
                    }
                    if isSpent {
                        Label {
                            Text("Spent by the last build", bundle: #bundle)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                        }
                        .labelStyle(.status(TWColor.success))
                        .font(.caption)
                    }
                }
            }
            .strikethrough(choice == .never, color: TWColor.secondaryText)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("utxoChoice-\(id)")
    }
}

/// A UTxO's token count, which opens the list of what it holds.
private struct TokensButton: View {
    let count: Int
    let tokens: [TransactionComposer.HeldToken]
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Label {
                Text("\(count) tokens", bundle: #bundle)
            } icon: {
                Image(systemName: "circle.hexagongrid")
            }
            .font(.caption)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(tokens.isEmpty)
        .popover(isPresented: $isShowing) {
            TokenList(tokens: tokens)
                .presentationCompactAdaptation(.sheet)
        }
        .accessibilityIdentifier("utxoTokens")
    }
}

/// Each token by policy, name and quantity.
private struct TokenList: View {
    let tokens: [TransactionComposer.HeldToken]

    var body: some View {
        List {
            ForEach(policies, id: \.self) { policy in
                Section {
                    ForEach(tokens.filter { $0.policyID == policy }) { token in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                                if let name = token.name {
                                    Text(verbatim: name)
                                } else {
                                    Text("Unnamed", bundle: #bundle).foregroundStyle(TWColor.secondaryText)
                                }
                                if !token.nameHex.isEmpty {
                                    TWBytesText(token.nameHex, font: TWFont.bytesSmall)
                                }
                            }
                            Spacer()
                            Text(verbatim: token.quantity).font(TWFont.figure)
                        }
                    }
                } header: {
                    TWBytesText(policy, font: TWFont.bytesSmall)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 240)
    }

    private var policies: [String] {
        tokens.map(\.policyID).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
