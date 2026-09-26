import SwiftUI
import TxWorkshopCore

/// Rewards withdrawn from a stake address.
struct WithdrawalDraftSection: View {
    @Binding var withdrawal: WithdrawalDraft
    let onRemove: () -> Void

    var body: some View {
        Section {
            TextField(text: $withdrawal.stakeAddress) { Text("Stake address (stake…)", bundle: #bundle) }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            TextField(value: $withdrawal.lovelace, format: .number) { Text("Lovelace", bundle: #bundle) }
                .font(TWFont.figure)
        } header: {
            RemovableHeader(title: Text("Withdrawal", bundle: #bundle), onRemove: onRemove)
        } footer: {
            Text("The whole reward balance: the ledger refuses any other amount.", bundle: #bundle)
        }
    }
}

/// A vote on a governance action.
struct VoteDraftSection: View {
    @Binding var vote: VoteDraft
    let onRemove: () -> Void

    var body: some View {
        Section {
            Picker(selection: $vote.voter) {
                Text("DRep", bundle: #bundle).tag(VoteDraft.Voter.drep)
                Text("Stake pool", bundle: #bundle).tag(VoteDraft.Voter.stakePool)
                Text("Constitutional committee", bundle: #bundle).tag(VoteDraft.Voter.committee)
            } label: {
                Text("Voter", bundle: #bundle)
            }
            TextField(text: $vote.voterID) {
                vote.voter == .stakePool ? Text("Pool (pool1… or hex)", bundle: #bundle) : Text("Key hash (hex)", bundle: #bundle)
            }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
            TextField(text: $vote.action) { Text("Governance action (transaction id#index)", bundle: #bundle) }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            Picker(selection: $vote.choice) {
                Text("Yes", bundle: #bundle).tag(VoteDraft.Choice.yes)
                Text("No", bundle: #bundle).tag(VoteDraft.Choice.no)
                Text("Abstain", bundle: #bundle).tag(VoteDraft.Choice.abstain)
            } label: {
                Text("Vote", bundle: #bundle)
            }
            .pickerStyle(.segmented)
            TextField(text: $vote.anchorURL) { Text("Rationale URL (optional)", bundle: #bundle) }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            TextField(text: $vote.anchorHash) { Text("Rationale hash (Blake2b-256, hex)", bundle: #bundle) }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
        } header: {
            RemovableHeader(title: Text("Vote", bundle: #bundle), onRemove: onRemove)
        }
    }
}

/// A governance action proposed.
struct ProposalDraftSection: View {
    @Binding var proposal: ProposalDraft
    let onRemove: () -> Void
    @State private var isTreasury = false
    @State private var payee = ""
    @State private var amount: UInt64?

    var body: some View {
        Section {
            Picker(selection: $isTreasury) {
                Text("Info action", bundle: #bundle).tag(false)
                Text("Treasury withdrawal", bundle: #bundle).tag(true)
            } label: {
                Text("Action", bundle: #bundle)
            }
            if isTreasury {
                TextField(text: $payee) { Text("Pay to stake address", bundle: #bundle) }
                    .font(TWFont.bytesSmall)
                    .autocorrectionDisabled()
                TextField(value: $amount, format: .number) { Text("Lovelace", bundle: #bundle) }
                    .font(TWFont.figure)
            }
            TextField(text: $proposal.returnAddress) { Text("Deposit return stake address", bundle: #bundle) }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            TextField(text: $proposal.anchorURL) { Text("Anchor URL", bundle: #bundle) }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            TextField(text: $proposal.anchorHash) { Text("Anchor hash (Blake2b-256, hex)", bundle: #bundle) }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
        } header: {
            RemovableHeader(title: Text("Proposal", bundle: #bundle), onRemove: onRemove)
        } footer: {
            Text("Pays the governance action deposit, returned to the stake address when the action ends.", bundle: #bundle)
        }
        .onAppear {
            if case .treasuryWithdrawal(let address, let lovelace) = proposal.kind {
                isTreasury = true
                payee = address
                amount = lovelace
            }
        }
        .onChange(of: isTreasury) { sync() }
        .onChange(of: payee) { sync() }
        .onChange(of: amount) { sync() }
    }

    private func sync() {
        proposal.kind = isTreasury ? .treasuryWithdrawal(stakeAddress: payee, lovelace: amount ?? 0) : .info
    }
}
