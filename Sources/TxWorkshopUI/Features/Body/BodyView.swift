import SwiftCardanoExplorers
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Certificates, withdrawals, governance and treasury fields.
struct BodyView: View {
    let inspection: LoadState<TransactionInspection>

    var body: some View {
        InspectionContainer(inspection: inspection, title: LocalizedStringResource("Certificates & Governance", bundle: #bundle)) { inspection in
            let view = inspection.view
            if view.certificates.isEmpty && view.withdrawals.isEmpty && view.votes.isEmpty
                && view.proposals.isEmpty && view.treasuryDonation == nil && view.currentTreasuryAmount == nil
            {
                ContentUnavailableView {
                    Label {
                        Text("Nothing Here", bundle: #bundle)
                    } icon: {
                        Image(systemName: "checkmark.seal")
                    }
                } description: {
                    Text("This transaction has no certificates, withdrawals, votes or proposals.", bundle: #bundle)
                }
            } else {
                Form {
                    if !view.certificates.isEmpty {
                        Section {
                            ForEach(view.certificates, id: \.index) { certificate in
                                CertificateRow(certificate: certificate)
                            }
                        } header: {
                            Text("Certificates", bundle: #bundle)
                        }
                    }
                    if !view.withdrawals.isEmpty {
                        Section {
                            ForEach(view.withdrawals, id: \.rewardAddress) { withdrawal in
                                TWFieldRow(LocalizedStringResource("\(withdrawal.credentialKind) credential", bundle: #bundle)) {
                                    VStack(alignment: .trailing) {
                                        Text(verbatim: TWFormat.ada(withdrawal.lovelace)).font(TWFont.figure)
                                        IdentifierLine(text: withdrawal.rewardAddress, item: ExplorerItem.account(withdrawal.rewardAddress))
                                    }
                                }
                            }
                        } header: {
                            Text("Withdrawals", bundle: #bundle)
                        }
                    }
                    if !view.votes.isEmpty {
                        Section {
                            ForEach(view.votes.enumerated(), id: \.offset) { _, vote in
                                VoteRow(vote: vote)
                            }
                        } header: {
                            Text("Votes", bundle: #bundle)
                        }
                    }
                    if !view.proposals.isEmpty {
                        Section {
                            ForEach(view.proposals, id: \.index) { proposal in
                                ProposalRow(proposal: proposal)
                            }
                        } header: {
                            Text("Proposals", bundle: #bundle)
                        }
                    }
                    if view.treasuryDonation != nil || view.currentTreasuryAmount != nil {
                        Section {
                            if let donation = view.treasuryDonation {
                                TWFieldRow(LocalizedStringResource("Donation", bundle: #bundle)) {
                                    Text(verbatim: TWFormat.ada(donation)).font(TWFont.figure)
                                }
                            }
                            if let current = view.currentTreasuryAmount {
                                TWFieldRow(LocalizedStringResource("Asserted balance", bundle: #bundle)) {
                                    Text(verbatim: TWFormat.ada(current)).font(TWFont.figure)
                                }
                            }
                        } header: {
                            Text("Treasury", bundle: #bundle)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}
