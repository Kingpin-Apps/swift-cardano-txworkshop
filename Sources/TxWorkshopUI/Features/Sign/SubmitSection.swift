import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Submits the signed transaction and follows it until it is on chain.
struct SubmitSection: View {
    let document: TxWorkshopDocument
    let isComplete: Bool
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(SubmissionTracker.self) private var tracker
    @Environment(\.undoManager) private var undoManager
    @State private var isSubmitting = false
    @State private var isConfirmingSubmit = false
    @State private var problem: String?

    private var provider: ProviderConfiguration? {
        document.content.network.flatMap { providers.selectedProvider(for: $0) }
    }

    var body: some View {
        Section {
            if let problem {
                Text(verbatim: problem).foregroundStyle(TWColor.failure)
            }
            Button {
                isConfirmingSubmit = true
            } label: {
                Text("Submit…", bundle: #bundle)
                    .opacity(isSubmitting ? 0 : 1)
                    .overlay { if isSubmitting { ProgressView() } }
            }
            .disabled(isSubmitting || provider == nil || !isComplete)
            ForEach(document.content.submissions.reversed()) { submission in
                HStack {
                    let confirmed = submission.confirmedAt ?? tracker.confirmedAt(submission.transactionID)
                    Image(systemName: confirmed == nil ? "clock" : "checkmark.circle.fill")
                        .foregroundStyle(confirmed == nil ? TWColor.warning : TWColor.success)
                    VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                        TWBytesText(submission.transactionID, font: TWFont.bytesSmall)
                        if let confirmed {
                            Text("On chain since \(confirmed, format: .dateTime)", bundle: #bundle).font(.caption)
                        } else {
                            Text("Submitted \(submission.submittedAt, format: .relative(presentation: .named)) through \(submission.provider); waiting", bundle: #bundle)
                                .font(.caption)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Submit", bundle: #bundle)
        } footer: {
            if let provider, let network = document.content.network {
                Text("Through \(provider.name), to \(Text(network.name)). You get a notification when it is on chain.", bundle: #bundle)
            } else {
                Text("Set the network and a provider for it to submit.", bundle: #bundle)
            }
        }
        .onChange(of: tracker.tracked, initial: true) { recordConfirmations() }
        .confirmationDialog(String(localized: "Submit this transaction?", bundle: #bundle), isPresented: $isConfirmingSubmit) {
            Button(action: submit) { Text("Submit", bundle: #bundle) }
        } message: {
            if let network = document.content.network {
                Text("It goes to \(Text(network.name)) and cannot be taken back once it is on chain.", bundle: #bundle)
            }
        }
    }

    /// Writes confirmations the tracker has seen into the document.
    private func recordConfirmations() {
        let confirmed = document.content.submissions.compactMap { submission -> (UUID, Date)? in
            guard submission.confirmedAt == nil, let date = tracker.confirmedAt(submission.transactionID) else { return nil }
            return (submission.id, date)
        }
        guard !confirmed.isEmpty else { return }
        document.update({ content in
            for (id, date) in confirmed {
                if let index = content.submissions.firstIndex(where: { $0.id == id }) { content.submissions[index].confirmedAt = date }
            }
        }, actionName: LocalizedStringResource("Record Confirmation", bundle: #bundle), undoManager: undoManager)
    }

    private func submit() {
        guard let provider, let bytes = document.content.transaction, let network = document.content.network else { return }
        let apiKey = providers.apiKey(for: provider)
        isSubmitting = true
        problem = nil
        Task {
            defer { isSubmitting = false }
            do {
                let id = try await TransactionSubmitter().submit(bytes, provider: provider, apiKey: apiKey)
                let record = SubmissionRecord(transactionID: id, network: network, provider: provider.name)
                document.update(
                    { $0.submissions.append(record) },
                    actionName: LocalizedStringResource("Submit", bundle: #bundle), undoManager: undoManager
                )
                tracker.track(id, provider: provider)
            } catch {
                problem = String(describing: error)
            }
        }
    }
}
