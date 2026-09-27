import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Where the builder may take funds from: watch-only addresses, and UTxOs
/// pasted or fetched from them.
struct SourcesSection: View {
    @Binding var recipe: BuildRecipe
    let provider: ProviderConfiguration?
    @Environment(ProviderSettingsStore.self) private var providers
    @State private var addresses = ""
    @State private var utxos = ""
    @State private var isFetching = false
    @State private var problem: String?

    var body: some View {
        Section {
            TextEditor(text: $addresses)
                .font(TWFont.bytesSmall)
                .frame(minHeight: 44, maxHeight: 120)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("Source addresses, one per line", bundle: #bundle))
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
            Text("One per line. Fetching saves their UTxOs in the recipe, so it builds offline later.", bundle: #bundle)
        }
        Section {
            TextEditor(text: $utxos)
                .font(TWFont.bytesSmall)
                .frame(minHeight: 44, maxHeight: 160)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("UTxOs as CBOR hex, one per line", bundle: #bundle))
            ForEach(recipe.utxos, id: \.self) { hex in
                if let described = TransactionComposer.describe(utxoHex: hex) {
                    HStack {
                        TWBytesText(described.id, font: TWFont.bytesSmall)
                        Spacer()
                        Text(verbatim: TWFormat.ada(described.lovelace)).font(TWFont.figure)
                    }
                } else {
                    Label {
                        Text("Not a UTxO: \(String(hex.prefix(16)))…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .labelStyle(.status(TWColor.warning))
                }
            }
        } header: {
            Text("UTxOs to spend", bundle: #bundle)
        } footer: {
            Text("Each a whole UTxO in CBOR hex, one per line.", bundle: #bundle)
        }
        .onAppear {
            addresses = recipe.sourceAddresses.joined(separator: "\n")
            utxos = recipe.utxos.joined(separator: "\n")
        }
        .onChange(of: addresses) { _, text in recipe.sourceAddresses = Self.lines(text) }
        .onChange(of: utxos) { _, text in recipe.utxos = Self.lines(text) }
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
