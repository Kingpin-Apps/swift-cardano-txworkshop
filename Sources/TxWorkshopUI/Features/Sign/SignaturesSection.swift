import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The signatures the transaction needs, which it has, and the stored keys
/// that can make the rest.
struct SignaturesSection: View {
    let needed: RequiredSignatures
    let keys: [StoredSigningKey]
    let onSign: (StoredSigningKey, [String]) -> Void

    private var missing: [String] { needed.signers.filter { !$0.isSigned }.map(\.keyHash) }

    var body: some View {
        Section {
            ForEach(needed.signers) { signer in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: signer.isSigned ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(signer.isSigned ? TWColor.success : TWColor.secondaryText)
                        .accessibilityLabel(signer.isSigned ? Text("Signed", bundle: #bundle) : Text("Not signed", bundle: #bundle))
                    VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                        TWBytesText(signer.keyHash, font: TWFont.bytesSmall)
                        Text(verbatim: signer.reasons.joined(separator: "; "))
                            .font(.caption)
                            .foregroundStyle(TWColor.secondaryText)
                        if let key = keys.first(where: { $0.keyHashes.contains(signer.keyHash) }) {
                            Text("Held by \(key.name)", bundle: #bundle)
                                .font(.caption)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if !needed.unresolvedInputs.isEmpty {
                Label {
                    Text(AttributedString(localized: "^[\(needed.unresolvedInputs.count) input](inflect: true) not looked up, so their signers are not listed. Fetch chain data in Validate.", bundle: #bundle))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .labelStyle(.status(TWColor.warning))
            }
            ForEach(keys.filter { !Set(missing).isDisjoint(with: $0.keyHashes) }) { key in
                Button {
                    onSign(key, missing)
                } label: {
                    Label {
                        Text("Sign with \(key.name)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "signature")
                    }
                }
            }
        } header: {
            Text("Signatures", bundle: #bundle)
        } footer: {
            if needed.isComplete {
                Text("Every signature it needs is here.", bundle: #bundle)
            } else if !needed.extraWitnesses.isEmpty {
                Text("It also carries signatures nothing asks for.", bundle: #bundle)
            }
        }
    }
}
