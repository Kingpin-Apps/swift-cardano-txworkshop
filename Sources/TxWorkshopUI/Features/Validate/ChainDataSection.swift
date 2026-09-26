import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// What chain data the document holds for validation, a way to fetch it,
/// and a way to type it in offline.
struct ChainDataSection: View {
    let document: TxWorkshopDocument
    let requirements: TransactionValidation.Requirements?
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.undoManager) private var undoManager
    @State private var isFetching = false
    @State private var problem: String?
    @State private var isEnteringByHand = false

    private var provider: ProviderConfiguration? {
        document.content.network.flatMap { providers.selectedProvider(for: $0) }
    }

    var body: some View {
        Section {
            if let snapshot = document.content.chainContext {
                TWFieldRow(LocalizedStringResource("Fetched", bundle: #bundle)) {
                    Text(snapshot.fetchedAt, format: .relative(presentation: .named))
                }
                if let slot = snapshot.tipSlot {
                    TWFieldRow(LocalizedStringResource("Tip slot", bundle: #bundle)) {
                        Text(slot, format: .number).font(TWFont.figure)
                    }
                }
            }
            if let requirements {
                RequirementRow(
                    isMet: !requirements.needsProtocolParameters,
                    met: LocalizedStringResource("Protocol parameters", bundle: #bundle),
                    unmet: LocalizedStringResource("No protocol parameters", bundle: #bundle)
                )
                RequirementRow(
                    isMet: requirements.missingInputs.isEmpty,
                    met: LocalizedStringResource("Every input's UTxO", bundle: #bundle),
                    unmet: LocalizedStringResource("\(requirements.missingInputs.count) inputs without their UTxO", bundle: #bundle)
                )
            }
            if let problem {
                Label {
                    Text(verbatim: problem)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(TWColor.failure)
            }
            Button(action: fetch) {
                Text("Fetch Chain Data", bundle: #bundle)
                    .opacity(isFetching ? 0 : 1)
                    .overlay { if isFetching { ProgressView() } }
            }
            .disabled(isFetching || provider == nil)
            Button {
                isEnteringByHand = true
            } label: {
                Text("Enter by Hand…", bundle: #bundle)
            }
        } header: {
            Text("Chain Data", bundle: #bundle)
        } footer: {
            if let provider {
                Text("Fetches inputs, protocol parameters, the tip and ledger state from \(provider.name), and saves them in the document for validating offline.", bundle: #bundle)
            } else if let network = document.content.network {
                Text("Add a provider for \(Text(network.name)) in Settings to fetch chain data, or enter it by hand.", bundle: #bundle)
            } else {
                Text("Set the network in Overview to fetch chain data, or enter it by hand.", bundle: #bundle)
            }
        }
        .sheet(isPresented: $isEnteringByHand) {
            ManualChainDataSheet(document: document, missingInputs: requirements?.missingInputs ?? [], undoManager: undoManager)
        }
    }

    private func fetch() {
        guard let provider, let bytes = document.content.transaction else { return }
        let apiKey = providers.apiKey(for: provider)
        let previous = document.content.chainContext
        isFetching = true
        problem = nil
        Task {
            defer { isFetching = false }
            do {
                let snapshot = try await ChainDataFetcher().fetch(transaction: bytes, provider: provider, apiKey: apiKey, keeping: previous)
                document.update(
                    { $0.chainContext = snapshot },
                    actionName: LocalizedStringResource("Fetch Chain Data", bundle: #bundle),
                    undoManager: undoManager
                )
            } catch {
                problem = String(describing: error)
            }
        }
    }
}

private struct RequirementRow: View {
    let isMet: Bool
    let met: LocalizedStringResource
    let unmet: LocalizedStringResource

    var body: some View {
        Label {
            Text(isMet ? met : unmet)
        } icon: {
            Image(systemName: isMet ? "checkmark.circle" : "circle.dashed")
                .foregroundStyle(isMet ? TWColor.success : TWColor.warning)
        }
    }
}
