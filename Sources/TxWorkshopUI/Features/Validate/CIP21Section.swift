import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Whether hardware wallets can sign the transaction (CIP-21), what is in the
/// way, and building it again so they can.
///
/// Writing a body the way CIP-21 asks changes its bytes, and with them the
/// transaction id and the fee the ledger charges. So the transaction is built
/// again for hardware wallets, with the fee worked out from the bytes that
/// will be signed, rather than its bytes rewritten.
struct CIP21Section: View {
    let document: TxWorkshopDocument
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.undoManager) private var undoManager
    @State private var report: LoadState<CIP21Report> = .idle
    @State private var proposal: CIP21Rebuild.Result?
    @State private var isRebuilding = false
    @State private var rebuildProblem: String?

    var body: some View {
        Section {
            switch report {
            case .idle, .loading:
                ProgressView()
            case .failed(let message):
                TWErrorText(message)
            case .loaded(let report):
                content(report)
            }
        } header: {
            Text("Hardware Wallets (CIP-21)", bundle: #bundle)
        } footer: {
            Text("Ledger, Trezor and Keystone sign only transactions written the way CIP-21 sets out.", bundle: #bundle)
        }
        .task(id: document.content.transaction) {
            rebuildProblem = nil
            check()
        }
        .confirmationDialog(
            Text("Rebuild for Hardware Wallets?", bundle: #bundle), isPresented: isProposing, titleVisibility: .visible,
            presenting: proposal
        ) { result in
            Button {
                apply(result)
            } label: {
                Text("Rebuild", bundle: #bundle)
            }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: #bundle) }
        } message: { result in
            Text(Self.message(result))
        }
    }

    @ViewBuilder private func content(_ report: CIP21Report) -> some View {
        LabeledContent {
            Text(Self.modeName(report.mode))
        } label: {
            Text("Signing mode", bundle: #bundle)
        }
        if report.isCompatible {
            Label {
                Text("Hardware wallets can sign it as written.", bundle: #bundle)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .labelStyle(.status(TWColor.success))
            .accessibilityIdentifier("cip21Compatible")
        } else {
            ForEach(report.findings) { finding in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: finding.message)
                        if let path = finding.path {
                            Text(verbatim: path)
                                .font(TWFont.bytesSmall)
                                .foregroundStyle(TWColor.secondaryText)
                        }
                    }
                } icon: {
                    Image(systemName: finding.fixable ? "wrench.and.screwdriver" : "xmark.octagon")
                }
                .labelStyle(.status(finding.fixable ? TWColor.warning : TWColor.failure))
            }
            if !report.fixable.isEmpty {
                Button {
                    rebuild()
                } label: {
                    Label {
                        Text("Rebuild for Hardware Wallets…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "wand.and.stars")
                    }
                }
                .disabled(isRebuilding)
                .accessibilityIdentifier("cip21Rebuild")
                if isRebuilding {
                    ProgressView()
                }
                if let rebuildProblem {
                    TWErrorText(rebuildProblem)
                }
            }
        }
    }

    private var isProposing: Binding<Bool> {
        Binding { proposal != nil } set: { if !$0 { proposal = nil } }
    }

    private func check() {
        guard let bytes = document.content.transaction else {
            report = .idle
            return
        }
        do {
            report = .loaded(try CIP21Check.report(bytes))
        } catch {
            report = .failed(String(describing: error))
        }
    }

    /// Builds the transaction again for hardware wallets: from the build
    /// form when the document has one, from the transaction otherwise.
    private func rebuild() {
        guard let bytes = document.content.transaction else { return }
        let content = document.content
        let provider = content.network.flatMap { providers.selectedProvider(for: $0) }
        let apiKey = provider.flatMap { providers.apiKey(for: $0) }
        isRebuilding = true
        rebuildProblem = nil
        Task {
            defer { isRebuilding = false }
            do {
                proposal = try await CIP21Rebuild.rebuild(
                    bytes, recipe: content.recipe, snapshot: content.chainContext, network: content.network,
                    provider: provider, apiKey: apiKey
                )
            } catch {
                rebuildProblem = String(describing: error)
            }
        }
    }

    private func apply(_ result: CIP21Rebuild.Result) {
        document.update({ content in
            content.transaction = result.transaction
            // Every signature, kept or collected, signed the old id.
            content.envelope = nil
            content.witnesses = []
            if let recipe = result.recipe {
                content.recipe = recipe
            }
        }, actionName: LocalizedStringResource("Rebuild for Hardware Wallets", bundle: #bundle), undoManager: undoManager)
        proposal = nil
    }

    static func message(_ result: CIP21Rebuild.Result) -> String {
        var lines: [String] = []
        switch result.source {
        case .recipe:
            lines.append(String(localized: "It is built again from its build form, for hardware wallets, spending the same inputs. The build form keeps building for hardware wallets.", bundle: #bundle))
        case .transaction:
            lines.append(String(localized: "It is built again from the transaction, for hardware wallets: the same inputs and outputs, with the change worked out again.", bundle: #bundle))
        }
        if result.fee == result.previousFee {
            lines.append(String(localized: "The fee stays \(result.fee) lovelace.", bundle: #bundle))
        } else {
            lines.append(String(localized: "The fee goes from \(result.previousFee) to \(result.fee) lovelace, worked out from the bytes that will be signed.", bundle: #bundle))
        }
        if result.droppedSignatures > 0 {
            lines.append(String(localized: "The transaction id changes, so its \(result.droppedSignatures) signatures are removed: sign it again.", bundle: #bundle))
        } else {
            lines.append(String(localized: "The transaction id changes: sign the new one.", bundle: #bundle))
        }
        if !result.report.isCompatible {
            lines.append(String(localized: "Still in the way: \(result.report.findings.map(\.message).joined(separator: " "))", bundle: #bundle))
        }
        return lines.joined(separator: "\n")
    }

    static func modeName(_ mode: CIP21SigningMode) -> LocalizedStringResource {
        switch mode {
        case .poolRegistration: LocalizedStringResource("Pool registration", bundle: #bundle)
        case .ordinary: LocalizedStringResource("Ordinary", bundle: #bundle)
        case .multisig: LocalizedStringResource("Multisig", bundle: #bundle)
        case .plutus: LocalizedStringResource("Plutus", bundle: #bundle)
        }
    }
}
