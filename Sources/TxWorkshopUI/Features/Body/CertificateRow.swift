import SwiftCardanoTxValidator
import SwiftUI
import TxWorkshopCore

struct CertificateRow: View {
    let certificate: CertificateView

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
            if let credential = certificate.credential { TWBytesText(credential, font: TWFont.bytesSmall) }
            if let pool = certificate.pool { TWBytesText("pool:\(pool)", font: TWFont.bytesSmall) }
            if let drep = certificate.drep { TWBytesText("drep:\(drep)", font: TWFont.bytesSmall) }
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
                    .foregroundStyle(vote.vote == "yes" ? TWColor.success : vote.vote == "no" ? TWColor.failure : TWColor.secondaryText)
            }
            TWBytesText(vote.voter, font: TWFont.bytesSmall)
            TWBytesText(vote.govActionId, font: TWFont.bytesSmall)
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
            TWBytesText(proposal.returnAddress, font: TWFont.bytesSmall)
            AnchorLine(url: proposal.anchorURL, hash: proposal.anchorHash)
        }
        .accessibilityElement(children: .contain)
    }
}
