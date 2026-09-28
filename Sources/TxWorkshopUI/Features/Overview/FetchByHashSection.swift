import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Looks a transaction up by id, or an explorer link to it, on every public
/// network: with the network's own Blockfrost or Koios provider, or else
/// Koios's public API, so it works before any provider is set up.
struct FetchByHashSection: View {
    let document: TxWorkshopDocument
    /// Called once the transaction is in the document.
    var onFetched: () -> Void = {}
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.undoManager) private var undoManager
    @State private var hash = ""
    @State private var isFetching = false
    @State private var problem: String?

    var body: some View {
        Section {
            TextField(text: $hash) {
                Text("Transaction id or explorer link", bundle: #bundle)
            }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
            #if os(iOS) || os(visionOS)
            .textInputAutocapitalization(.never)
            #endif
            .onSubmit(fetch)
            if let problem {
                Label {
                    Text(verbatim: problem)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .labelStyle(.status(TWColor.failure))
            }
            Button(action: fetch) {
                Text("Fetch Transaction", bundle: #bundle)
                    .opacity(isFetching ? 0 : 1)
                    .overlay { if isFetching { ProgressView() } }
            }
            .disabled(isFetching || hash.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Fetch by id", bundle: #bundle)
        } footer: {
            Text("Searches mainnet, preprod and preview, with your Blockfrost or Koios provider where you have one and Koios's public API elsewhere.", bundle: #bundle)
        }
    }

    private func fetch() {
        guard !isFetching, !hash.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let sources = TransactionFetcher.withPublicFallback(CardanoNetwork.allCases.compactMap { network in
            providers.selectedProvider(for: network).map {
                TransactionFetcher.Source(provider: $0, apiKey: providers.apiKey(for: $0))
            }
        })
        let hash = hash
        isFetching = true
        problem = nil
        Task {
            defer { isFetching = false }
            do {
                let fetched = try await TransactionFetcher().fetch(hash: hash, from: sources)
                document.update({ content in
                    content.transaction = fetched.cbor
                    content.envelope = nil
                    content.network = fetched.network
                }, actionName: LocalizedStringResource("Fetch Transaction", bundle: #bundle), undoManager: undoManager)
                onFetched()
            } catch {
                problem = String(describing: error)
            }
        }
    }
}
