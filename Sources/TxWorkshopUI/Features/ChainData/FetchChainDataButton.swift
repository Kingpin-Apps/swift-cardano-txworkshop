import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Fetches the document's chain data where something needs it, then calls
/// `onFetched` to try again. Without a provider it says where to add one.
struct FetchChainDataButton: View {
    let document: TxWorkshopDocument
    let onFetched: () -> Void
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.undoManager) private var undoManager
    @State private var isFetching = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: TWSpacing.s) {
            if ChainDataFetch.provider(for: document, in: providers) != nil {
                Button {
                    fetch()
                } label: {
                    Text("Fetch Chain Data", bundle: #bundle)
                        .opacity(isFetching ? 0 : 1)
                        .overlay { if isFetching { ProgressView() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFetching)
                .accessibilityIdentifier("fetchChainDataHere")
            } else {
                Text("Add a provider in Settings, or enter chain data by hand in Chain Data.", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if let problem { TWErrorText(problem) }
        }
    }

    private func fetch() {
        isFetching = true
        problem = nil
        Task {
            defer { isFetching = false }
            do {
                try await ChainDataFetch.run(document: document, providers: providers, undoManager: undoManager)
                onFetched()
            } catch {
                problem = String(describing: error)
            }
        }
    }
}
