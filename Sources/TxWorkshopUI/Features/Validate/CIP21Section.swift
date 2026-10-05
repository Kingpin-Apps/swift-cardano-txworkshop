import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Whether hardware wallets can sign the transaction (CIP-21), what is in the
/// way, and a rewrite that fixes what can be fixed.
struct CIP21Section: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager
    @State private var report: LoadState<CIP21Report> = .idle
    @State private var proposal: CIP21Transform.Result?

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
        .task(id: document.content.transaction) { check() }
        .confirmationDialog(
            Text("Rewrite for Hardware Wallets?", bundle: #bundle), isPresented: isProposing, titleVisibility: .visible,
            presenting: proposal
        ) { result in
            Button {
                apply(result)
            } label: {
                Text("Rewrite", bundle: #bundle)
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
                    propose()
                } label: {
                    Label {
                        Text("Make CIP-21 Compatible…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "wand.and.stars")
                    }
                }
                .accessibilityIdentifier("cip21Rewrite")
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

    private func propose() {
        guard let bytes = document.content.transaction else { return }
        do {
            proposal = try CIP21Transform.compatible(bytes)
        } catch {
            report = .failed(String(describing: error))
        }
    }

    private func apply(_ result: CIP21Transform.Result) {
        guard result.changed else { return }
        document.update({ content in
            content.transaction = result.bytes
            if result.droppedSignatures > 0 {
                // They signed the old body.
                content.envelope = nil
                content.witnesses = []
            }
        }, actionName: LocalizedStringResource("Rewrite for Hardware Wallets", bundle: #bundle), undoManager: undoManager)
        proposal = nil
    }

    static func message(_ result: CIP21Transform.Result) -> String {
        var lines = result.changes
        if result.droppedSignatures > 0 {
            lines.append(String(localized: "The transaction id changes, so its \(result.droppedSignatures) signatures are removed: sign it again.", bundle: #bundle))
        }
        if !result.remaining.isEmpty {
            lines.append(String(localized: "Still in the way, which a rewrite cannot fix: \(result.remaining.map(\.message).joined(separator: " "))", bundle: #bundle))
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
