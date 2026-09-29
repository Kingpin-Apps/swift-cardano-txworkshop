import SwiftCardanoExplorers
import SwiftCardanoTxValidator
import SwiftUI
import TxWorkshopCore

struct CertificateRow: View {
    let certificate: CertificateView
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
            if let credential = certificate.credential {
                IdentifierLine(text: credential, item: ExplorerItem.account(credential: credential, network: network))
            }
            if let pool = certificate.pool { IdentifierLine(text: "pool:\(pool)", item: ExplorerItem.pool(pool)) }
            if let drep = certificate.drep { IdentifierLine(text: "drep:\(drep)", item: ExplorerItem.drep(drep)) }
            if let url = certificate.anchorURL { AnchorLine(url: url, hash: certificate.anchorHash) }
        }
        .accessibilityElement(children: .contain)
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

/// An identifier, with a link to it in the chosen explorer.
struct IdentifierLine: View {
    let text: String
    let item: ExplorerItem?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TWBytesText(text, font: TWFont.bytesSmall)
            ExplorerLinkButton(item: item)
        }
    }
}
