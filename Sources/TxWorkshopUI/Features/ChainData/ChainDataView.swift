import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The chain data a document keeps for validating, debugging and building
/// offline: where it came from, the tip, epoch and era, the protocol
/// parameters, and whether every input's UTxO is there.
struct ChainDataView: View {
    let document: TxWorkshopDocument
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.undoManager) private var undoManager
    @State private var isFetching = false
    @State private var problem: String?
    @State private var isEnteringByHand = false
    @State private var requirements: TransactionValidation.Requirements?
    @State private var showsAllParameters = false

    private var provider: ProviderConfiguration? { ChainDataFetch.provider(for: document, in: providers) }
    private var summary: ChainSummary? { document.content.chainContext.map(ChainSummary.init) }

    var body: some View {
        Form {
            source
            if let summary {
                chain(summary)
                if !summary.parameters.isEmpty { parameters(summary) }
            }
            if let requirements, document.content.transaction != nil { inputs(requirements) }
        }
        .formStyle(.grouped)
        .twScreenBackground()
        .navigationTitle(Text("Chain Data", bundle: #bundle))
        .task(id: RequirementsKey(transaction: document.content.transaction, snapshot: document.content.chainContext)) {
            guard let bytes = document.content.transaction else { requirements = nil; return }
            requirements = try? TransactionValidation().requirements(for: bytes, snapshot: document.content.chainContext)
        }
        .sheet(isPresented: $isEnteringByHand) {
            ManualChainDataSheet(document: document, missingInputs: requirements?.missingInputs ?? [], undoManager: undoManager)
        }
    }

    private struct RequirementsKey: Equatable {
        let transaction: Data?
        let snapshot: ChainContextSnapshot?
    }

    // MARK: - Sections

    private var source: some View {
        Section {
            if let summary {
                TWFieldRow(LocalizedStringResource("Fetched", bundle: #bundle)) {
                    Text(summary.fetchedAt, format: .relative(presentation: .named))
                }
            } else {
                Text("No chain data yet.", bundle: #bundle)
                    .foregroundStyle(TWColor.secondaryText)
            }
            if let provider {
                TWFieldRow(LocalizedStringResource("Provider", bundle: #bundle)) {
                    Text(verbatim: provider.name)
                }
            }
            if let problem { TWErrorText(problem) }
            Button(action: fetch) {
                Label {
                    Text(summary == nil ? String(localized: "Fetch Chain Data", bundle: #bundle) : String(localized: "Refresh Chain Data", bundle: #bundle))
                        .opacity(isFetching ? 0 : 1)
                        .overlay { if isFetching { ProgressView() } }
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .disabled(isFetching || provider == nil)
            .accessibilityIdentifier("fetchChainData")
            Button {
                isEnteringByHand = true
            } label: {
                Label {
                    Text("Enter by Hand…", bundle: #bundle)
                } icon: {
                    Image(systemName: "keyboard")
                }
            }
        } header: {
            Text("Source", bundle: #bundle)
        } footer: {
            if let provider {
                if document.content.transaction == nil {
                    Text("Fetches the protocol parameters, the tip, the epoch and the era from \(provider.name). With a transaction, its inputs and ledger state come too.", bundle: #bundle)
                } else {
                    Text("Fetches the transaction's inputs, the protocol parameters, the tip and the ledger state from \(provider.name), and keeps them in the document for working offline.", bundle: #bundle)
                }
            } else if let network = document.content.network {
                Text("Add a provider for \(Text(network.name)) in Settings to fetch chain data, or enter it by hand.", bundle: #bundle)
            } else {
                Text("Set the network in Overview to fetch chain data, or enter it by hand.", bundle: #bundle)
            }
        }
    }

    private func chain(_ summary: ChainSummary) -> some View {
        Section {
            if let slot = summary.tipSlot {
                TWFieldRow(LocalizedStringResource("Tip slot", bundle: #bundle)) {
                    Text(slot, format: .number).font(TWFont.figure)
                }
            }
            if let epoch = summary.epoch {
                TWFieldRow(LocalizedStringResource("Epoch", bundle: #bundle)) {
                    Text(epoch, format: .number).font(TWFont.figure)
                }
            }
            if let era = summary.era {
                TWFieldRow(LocalizedStringResource("Era", bundle: #bundle)) {
                    Text(verbatim: era.capitalized)
                }
            }
            if let version = summary.protocolVersion {
                TWFieldRow(LocalizedStringResource("Protocol version", bundle: #bundle)) {
                    Text(verbatim: version).font(TWFont.figure)
                }
            }
            TWFieldRow(LocalizedStringResource("UTxOs kept", bundle: #bundle)) {
                Text(summary.utxoCount, format: .number).font(TWFont.figure)
            }
        } header: {
            Text("Chain", bundle: #bundle)
        }
    }

    private func parameters(_ summary: ChainSummary) -> some View {
        Section {
            ForEach(summary.parameters) { row in
                LabeledContent {
                    Text(verbatim: row.value)
                        .font(TWFont.figure)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Text(verbatim: row.name)
                }
            }
            ForEach(summary.costModels) { row in
                LabeledContent {
                    Text(verbatim: row.value).font(TWFont.figure)
                } label: {
                    Text("Cost model, \(row.name)", bundle: #bundle)
                }
            }
            DisclosureGroup(isExpanded: $showsAllParameters) {
                Text(verbatim: summary.parametersJSON)
                    .font(TWFont.bytesSmall)
                    .textSelection(.enabled)
            } label: {
                Text("All Parameters", bundle: #bundle)
            }
        } header: {
            Text("Protocol Parameters", bundle: #bundle)
        }
    }

    private func inputs(_ requirements: TransactionValidation.Requirements) -> some View {
        Section {
            Label {
                if requirements.missingInputs.isEmpty {
                    Text("Every input's UTxO is here.", bundle: #bundle)
                } else {
                    Text("\(requirements.missingInputs.count) inputs without their UTxO", bundle: #bundle)
                }
            } icon: {
                Image(systemName: requirements.missingInputs.isEmpty ? "checkmark.circle" : "circle.dashed")
            }
            .labelStyle(.status(requirements.missingInputs.isEmpty ? TWColor.success : TWColor.warning))
            ForEach(requirements.missingInputs, id: \.self) { input in
                CopyableBytes(input)
            }
            if requirements.allInputsSpent {
                Text("Every input is already spent: the transaction is likely on chain.", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
            }
        } header: {
            Text("The Transaction's Inputs", bundle: #bundle)
        }
    }

    private func fetch() {
        isFetching = true
        problem = nil
        Task {
            defer { isFetching = false }
            do {
                try await ChainDataFetch.run(document: document, providers: providers, undoManager: undoManager)
            } catch {
                problem = String(describing: error)
            }
        }
    }
}
