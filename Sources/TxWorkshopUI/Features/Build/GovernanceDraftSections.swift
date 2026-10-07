import SwiftUI
import TxWorkshopCore

/// Rewards withdrawn from a stake address.
struct WithdrawalDraftSection: View {
    @Binding var withdrawal: WithdrawalDraft
    let onRemove: () -> Void

    var body: some View {
        Section {
            ValueField(kind: .stakeAddress, text: $withdrawal.stakeAddress, prompt: Text("Stake address, key hash or stake key", bundle: #bundle))
            TWLabeledField(Text("Lovelace", bundle: #bundle), value: $withdrawal.lovelace, format: .number)
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
            switch vote.voter {
            case .drep:
                ValueField(kind: .drepKeyHash, text: $vote.voterID, prompt: Text("DRep id, key hash or key file", bundle: #bundle))
            case .stakePool:
                ValueField(kind: .pool, text: $vote.voterID, prompt: Text("Pool id, hex, cold key or pool.json", bundle: #bundle))
            case .committee:
                ValueField(kind: .committeeHotKeyHash, text: $vote.voterID, prompt: Text("Committee hot id, key hash or hot key file", bundle: #bundle))
            }
            ValueField(kind: .govActionID, text: $vote.action, prompt: Text("Governance action (gov_action1… or transaction id#index)", bundle: #bundle))
            Picker(selection: $vote.choice) {
                Text("Yes", bundle: #bundle).tag(VoteDraft.Choice.yes)
                Text("No", bundle: #bundle).tag(VoteDraft.Choice.no)
                Text("Abstain", bundle: #bundle).tag(VoteDraft.Choice.abstain)
            } label: {
                Text("Vote", bundle: #bundle)
            }
            .pickerStyle(.segmented)
            TWLabeledField(Text("Rationale URL (optional)", bundle: #bundle), text: $vote.anchorURL)
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            AnchorHashField(hash: $vote.anchorHash, url: vote.anchorURL, prompt: Text("Rationale hash (hex, or choose the rationale file)", bundle: #bundle))
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
                ValueField(kind: .stakeAddress, text: $payee, prompt: Text("Pay to stake address", bundle: #bundle))
                TWLabeledField(Text("Lovelace", bundle: #bundle), value: $amount, format: .number)
                    .font(TWFont.figure)
            }
            ValueField(kind: .stakeAddress, text: $proposal.returnAddress, prompt: Text("Deposit return stake address", bundle: #bundle))
            TWLabeledField(Text("Anchor URL", bundle: #bundle), text: $proposal.anchorURL)
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            AnchorHashField(hash: $proposal.anchorHash, url: proposal.anchorURL, prompt: Text("Anchor hash (hex, or choose the anchor file)", bundle: #bundle))
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
