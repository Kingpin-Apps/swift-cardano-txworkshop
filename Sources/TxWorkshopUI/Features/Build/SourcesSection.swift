import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Where the builder may take funds from: watch-only addresses, and UTxOs
/// pasted or fetched from them, each spent when coin selection picks it,
/// always, or never.
struct SourcesSection: View {
    @Binding var recipe: BuildRecipe
    let provider: ProviderConfiguration?
    /// What the last build spent, so an input it picked can be left out even
    /// when it was not fetched here.
    var spent: [TransactionComposer.SpentInput] = []
    @Environment(ProviderSettingsStore.self) private var providers
    @State private var utxos = ""
    @State private var isFetching = false
    @State private var problem: String?

    var body: some View {
        Section {
            ValueLinesEditor(kind: .address, lines: $recipe.sourceAddresses, label: Text("Source addresses, one per line", bundle: #bundle))
            Button(action: fetch) {
                Text("Fetch Their UTxOs", bundle: #bundle)
                    .opacity(isFetching ? 0 : 1)
                    .overlay { if isFetching { ProgressView() } }
            }
            .disabled(isFetching || provider == nil || recipe.sourceAddresses.isEmpty)
            if let problem {
                TWErrorText(problem)
            }
        } header: {
            Text("Source addresses", bundle: #bundle)
        } footer: {
            Text("One per line: bech32, hex, or read from .addr or payment key files. Fetching saves their UTxOs in the recipe, so it builds offline later.", bundle: #bundle)
        }
        Section {
            TextEditor(text: $utxos)
                .font(TWFont.bytesSmall)
                .frame(minHeight: 44, maxHeight: 160)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("UTxOs as CBOR hex, one per line", bundle: #bundle))
            ForEach(recipe.utxos, id: \.self) { hex in
                if let described = TransactionComposer.describe(utxoHex: hex) {
                    UTxOChoiceRow(
                        id: described.id, lovelace: described.lovelace, assetCount: described.assetCount,
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
                    id: input.id, lovelace: input.lovelace, assetCount: input.assetCount,
                    isSpent: spentIDs.contains(input.id), choice: choice(for: input.id)
                )
            }
        } header: {
            Text("UTxOs to spend", bundle: #bundle)
        } footer: {
            Text("Each a whole UTxO in CBOR hex, one per line. Coin selection picks from them automatically; choose Always Use or Don't Use to decide yourself, for example to leave out a UTxO another transaction still being signed spends.", bundle: #bundle)
        }
        .onAppear {
            utxos = recipe.utxos.joined(separator: "\n")
        }
        .onChange(of: utxos) { _, text in recipe.utxos = Self.lines(text) }
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

    private func fetch() {
        guard let provider else { return }
        let addresses = recipe.sourceAddresses
        let apiKey = providers.apiKey(for: provider)
        isFetching = true
        problem = nil
        Task {
            defer { isFetching = false }
            do {
                let found = try await TransactionComposer().utxos(at: addresses, provider: provider, apiKey: apiKey)
                var merged = recipe.utxos
                for hex in found where !merged.contains(hex) { merged.append(hex) }
                utxos = merged.joined(separator: "\n")
            } catch {
                problem = String(describing: error)
            }
        }
    }
}

/// One UTxO, what it holds, whether the last build spent it, and how coin
/// selection should treat it.
private struct UTxOChoiceRow: View {
    let id: String
    let lovelace: Int64
    let assetCount: Int
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
                        Text("\(assetCount) tokens", bundle: #bundle)
                            .font(.caption)
                            .foregroundStyle(TWColor.secondaryText)
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
