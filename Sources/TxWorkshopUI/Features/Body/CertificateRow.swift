import SwiftCardanoExplorers
import SwiftCardanoTxValidator
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A certificate: what it does, its deposit or refund, and every field in
/// it, as Build would ask for them.
struct CertificateRow: View {
    let certificate: CertificateView
    /// Its fields, read from the transaction.
    var detail: CertificateDetail?
    @Environment(\.documentNetwork) private var network

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            HStack {
                Text(verbatim: "\(certificate.index). \(certificate.summary)")
                Spacer()
                if let deposit = certificate.deposit {
                    Text(verbatim: TWFormat.ada(deposit))
                        .font(TWFont.figure)
                        .foregroundStyle(deposit < 0 ? TWColor.success : Color.primary)
                }
            }
            if let detail, !detail.fields.isEmpty {
                ForEach(detail.fields) { field in
                    CertificateFieldLine(field: field, network: network)
                }
            } else {
                if let credential = certificate.credential {
                    IdentifierLine(text: credential, item: ExplorerItem.account(credential: credential, network: network))
                }
                if let pool = certificate.pool { IdentifierLine(text: "pool:\(pool)", item: ExplorerItem.pool(pool)) }
                if let drep = certificate.drep { IdentifierLine(text: "drep:\(drep)", item: ExplorerItem.drep(drep)) }
                if let url = certificate.anchorURL { AnchorLine(url: url, hash: certificate.anchorHash) }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One field of a certificate: its name above its value, which links to the
/// explorer when it names something there.
private struct CertificateFieldLine: View {
    let field: CertificateDetail.Field
    let network: CardanoNetwork?

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            Text(verbatim: field.label)
                .font(.caption)
                .foregroundStyle(TWColor.secondaryText)
            switch field.kind {
            case .text:
                Text(verbatim: field.value).textSelection(.enabled)
            case .lovelace(let lovelace):
                Text(verbatim: TWFormat.ada(lovelace)).font(TWFont.figure)
            case .identifier:
                CopyableBytes(field.value)
            case .pool:
                IdentifierLine(text: field.value, item: ExplorerItem.pool(field.value))
            case .stakeAddress:
                IdentifierLine(text: field.value, item: ExplorerItem.account(field.value))
            case .drep:
                IdentifierLine(text: field.value, item: ExplorerItem.drep(field.value))
            case .url:
                if let url = URL(string: field.value), url.scheme?.hasPrefix("http") == true {
                    Link(destination: url) {
                        Text(verbatim: field.value).font(TWFont.bytesSmall).multilineTextAlignment(.leading)
                    }
                } else {
                    TWBytesText(field.value, font: TWFont.bytesSmall)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct VoteRow: View {
    let vote: VoteView

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            HStack {
                Text(verbatim: vote.voterRole.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TWColor.secondaryText)
                Spacer()
                Text(verbatim: vote.vote.capitalized)
                    .fontWeight(.medium)
            }
            IdentifierLine(text: vote.voter, item: ExplorerItem.voter(role: vote.voterRole, credential: vote.voter))
            IdentifierLine(text: vote.govActionId, item: ExplorerItem.governanceAction(vote.govActionId))
            if let url = vote.anchorURL { AnchorLine(url: url, hash: vote.anchorHash) }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ProposalRow: View {
    let proposal: ProposalView

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            HStack {
                Text(verbatim: "\(proposal.index). \(proposal.actionType)")
                Spacer()
                Text(verbatim: TWFormat.ada(proposal.deposit)).font(TWFont.figure)
            }
            IdentifierLine(text: proposal.returnAddress, item: ExplorerItem.account(proposal.returnAddress))
            AnchorLine(url: proposal.anchorURL, hash: proposal.anchorHash)
        }
        .accessibilityElement(children: .contain)
    }
}

/// An identifier, with buttons to copy it and to open it in the chosen
/// explorer.
struct IdentifierLine: View {
    let text: String
    let item: ExplorerItem?

    var body: some View {
        CopyableBytes(text, item: item)
    }
}
