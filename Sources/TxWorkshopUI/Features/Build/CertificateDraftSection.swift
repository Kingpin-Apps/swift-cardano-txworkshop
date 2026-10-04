import SwiftUI
import TxWorkshopCore

/// One certificate: its kind, then the fields that kind needs. Every
/// certificate the Conway ledger accepts can be made here.
struct CertificateDraftSection: View {
    @Binding var item: CertificateItem
    let onRemove: () -> Void
    @State private var kind = Kind.registerStake
    @State private var stakeAddress = ""
    @State private var pool = ""
    @State private var drep = ""
    /// A DRep key, or a committee member's cold key.
    @State private var keyHash = ""
    @State private var hotKey = ""
    @State private var anchorURL = ""
    @State private var anchorHash = ""
    @State private var epoch: UInt64?
    @State private var poolDraft = PoolRegistrationDraft()

    enum Kind: Hashable, CaseIterable {
        case registerStake, deregisterStake, registerStakeLegacy, deregisterStakeLegacy
        case delegateStake, delegateVote, delegateStakeAndVote
        case registerAndDelegateStake, registerAndDelegateVote, registerAndDelegateStakeAndVote
        case registerPool, retirePool
        case registerDRep, unregisterDRep, updateDRep
        case authorizeCommitteeHot, resignCommitteeCold

        var needsStakeAddress: Bool {
            switch self {
            case .registerStake, .deregisterStake, .registerStakeLegacy, .deregisterStakeLegacy, .delegateStake, .delegateVote,
                .delegateStakeAndVote, .registerAndDelegateStake, .registerAndDelegateVote, .registerAndDelegateStakeAndVote: true
            default: false
            }
        }

        var needsPool: Bool {
            [.delegateStake, .delegateStakeAndVote, .registerAndDelegateStake, .registerAndDelegateStakeAndVote, .retirePool].contains(self)
        }

        var needsDRep: Bool {
            [.delegateVote, .delegateStakeAndVote, .registerAndDelegateVote, .registerAndDelegateStakeAndVote].contains(self)
        }
    }

    var body: some View {
        Section {
            Picker(selection: $kind) {
                Section {
                    Text("Register stake address", bundle: #bundle).tag(Kind.registerStake)
                    Text("Deregister stake address", bundle: #bundle).tag(Kind.deregisterStake)
                    Text("Register stake address (pre-Conway)", bundle: #bundle).tag(Kind.registerStakeLegacy)
                    Text("Deregister stake address (pre-Conway)", bundle: #bundle).tag(Kind.deregisterStakeLegacy)
                } header: {
                    Text("Stake address", bundle: #bundle)
                }
                Section {
                    Text("Delegate stake to a pool", bundle: #bundle).tag(Kind.delegateStake)
                    Text("Delegate votes to a DRep", bundle: #bundle).tag(Kind.delegateVote)
                    Text("Delegate stake and votes", bundle: #bundle).tag(Kind.delegateStakeAndVote)
                    Text("Register and delegate stake", bundle: #bundle).tag(Kind.registerAndDelegateStake)
                    Text("Register and delegate votes", bundle: #bundle).tag(Kind.registerAndDelegateVote)
                    Text("Register and delegate stake and votes", bundle: #bundle).tag(Kind.registerAndDelegateStakeAndVote)
                } header: {
                    Text("Delegation", bundle: #bundle)
                }
                Section {
                    Text("Register or update a stake pool", bundle: #bundle).tag(Kind.registerPool)
                    Text("Retire a stake pool", bundle: #bundle).tag(Kind.retirePool)
                } header: {
                    Text("Stake pool", bundle: #bundle)
                }
                Section {
                    Text("Register as a DRep", bundle: #bundle).tag(Kind.registerDRep)
                    Text("Retire as a DRep", bundle: #bundle).tag(Kind.unregisterDRep)
                    Text("Update DRep metadata", bundle: #bundle).tag(Kind.updateDRep)
                } header: {
                    Text("DRep", bundle: #bundle)
                }
                Section {
                    Text("Authorize a committee hot key", bundle: #bundle).tag(Kind.authorizeCommitteeHot)
                    Text("Resign from the committee", bundle: #bundle).tag(Kind.resignCommitteeCold)
                } header: {
                    Text("Constitutional committee", bundle: #bundle)
                }
            } label: {
                Text("Certificate", bundle: #bundle)
            }
            fields
        } header: {
            RemovableHeader(title: Text("Certificate", bundle: #bundle), onRemove: onRemove)
        } footer: {
            footer
        }
        .onAppear(perform: load)
        .onChange(of: kind) { sync() }
        .onChange(of: stakeAddress) { sync() }
        .onChange(of: pool) { sync() }
        .onChange(of: drep) { sync() }
        .onChange(of: keyHash) { sync() }
        .onChange(of: hotKey) { sync() }
        .onChange(of: anchorURL) { sync() }
        .onChange(of: anchorHash) { sync() }
        .onChange(of: epoch) { sync() }
        .onChange(of: poolDraft) { sync() }
    }

    @ViewBuilder private var fields: some View {
        if kind.needsStakeAddress {
            ValueField(kind: .stakeAddress, text: $stakeAddress, prompt: Text("Stake address, key hash or stake key", bundle: #bundle))
        }
        if kind.needsPool {
            ValueField(kind: .pool, text: $pool, prompt: Text("Pool id, hex, cold key or pool.json", bundle: #bundle))
        }
        if kind.needsDRep {
            ValueField(kind: .drep, text: $drep, prompt: Text("DRep id, key hash, key file, abstain or no-confidence", bundle: #bundle))
        }
        switch kind {
        case .retirePool:
            TextField(value: $epoch, format: .number.grouping(.never)) {
                Text("Retirement epoch", bundle: #bundle)
            }
            .font(TWFont.figure)
        case .registerPool:
            PoolRegistrationFields(draft: $poolDraft)
        case .registerDRep, .unregisterDRep, .updateDRep:
            ValueField(kind: .drepKeyHash, text: $keyHash, prompt: Text("DRep id, key hash or DRep key file", bundle: #bundle))
            if kind != .unregisterDRep { anchorFields }
        case .authorizeCommitteeHot, .resignCommitteeCold:
            ValueField(kind: .committeeColdKeyHash, text: $keyHash, prompt: Text("Committee cold id, key hash or cold key file", bundle: #bundle))
            if kind == .authorizeCommitteeHot {
                ValueField(kind: .committeeHotKeyHash, text: $hotKey, prompt: Text("Committee hot id, key hash or hot key file", bundle: #bundle))
            } else {
                anchorFields
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var anchorFields: some View {
        TextField(text: $anchorURL) { Text("Anchor URL (optional)", bundle: #bundle) }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
        AnchorHashField(hash: $anchorHash, url: anchorURL, prompt: Text("Anchor hash (hex, or choose the anchor file)", bundle: #bundle))
    }

    @ViewBuilder private var footer: some View {
        switch kind {
        case .registerStake, .registerStakeLegacy, .registerDRep, .registerAndDelegateStake, .registerAndDelegateVote,
            .registerAndDelegateStakeAndVote:
            Text("Pays the deposit the protocol parameters set.", bundle: #bundle)
        case .deregisterStake, .deregisterStakeLegacy, .unregisterDRep:
            Text("Takes the deposit back.", bundle: #bundle)
        case .registerPool:
            if poolDraft.isUpdate {
                Text("Updates a registered pool: no deposit. Signed by the pool's cold key and every owner.", bundle: #bundle)
            } else {
                Text("Pays the pool deposit the protocol parameters set. Signed by the pool's cold key and every owner.", bundle: #bundle)
            }
        case .retirePool:
            Text("Retires the pool at the start of that epoch: after the current one, and within the protocol's limit. The deposit returns to the reward account then. Signed by the cold key.", bundle: #bundle)
        default:
            EmptyView()
        }
    }

    private func load() {
        switch item.certificate {
        case .registerStake(let address): kind = .registerStake; stakeAddress = address
        case .deregisterStake(let address): kind = .deregisterStake; stakeAddress = address
        case .registerStakeLegacy(let address): kind = .registerStakeLegacy; stakeAddress = address
        case .deregisterStakeLegacy(let address): kind = .deregisterStakeLegacy; stakeAddress = address
        case .delegateStake(let address, let p): kind = .delegateStake; stakeAddress = address; pool = p
        case .delegateVote(let address, let d): kind = .delegateVote; stakeAddress = address; drep = d
        case .delegateStakeAndVote(let address, let p, let d): kind = .delegateStakeAndVote; stakeAddress = address; pool = p; drep = d
        case .registerAndDelegateStake(let address, let p): kind = .registerAndDelegateStake; stakeAddress = address; pool = p
        case .registerAndDelegateVote(let address, let d): kind = .registerAndDelegateVote; stakeAddress = address; drep = d
        case .registerAndDelegateStakeAndVote(let address, let p, let d):
            kind = .registerAndDelegateStakeAndVote; stakeAddress = address; pool = p; drep = d
        case .registerPool(let draft): kind = .registerPool; poolDraft = draft
        case .retirePool(let p, let e): kind = .retirePool; pool = p; epoch = e
        case .registerDRep(let hash, let url, let anchor): kind = .registerDRep; keyHash = hash; anchorURL = url; anchorHash = anchor
        case .unregisterDRep(let hash): kind = .unregisterDRep; keyHash = hash
        case .updateDRep(let hash, let url, let anchor): kind = .updateDRep; keyHash = hash; anchorURL = url; anchorHash = anchor
        case .authorizeCommitteeHot(let cold, let hot): kind = .authorizeCommitteeHot; keyHash = cold; hotKey = hot
        case .resignCommitteeCold(let cold, let url, let anchor): kind = .resignCommitteeCold; keyHash = cold; anchorURL = url; anchorHash = anchor
        }
    }

    private func sync() {
        item.certificate = switch kind {
        case .registerStake: .registerStake(stakeAddress: stakeAddress)
        case .deregisterStake: .deregisterStake(stakeAddress: stakeAddress)
        case .registerStakeLegacy: .registerStakeLegacy(stakeAddress: stakeAddress)
        case .deregisterStakeLegacy: .deregisterStakeLegacy(stakeAddress: stakeAddress)
        case .delegateStake: .delegateStake(stakeAddress: stakeAddress, pool: pool)
        case .delegateVote: .delegateVote(stakeAddress: stakeAddress, drep: drep)
        case .delegateStakeAndVote: .delegateStakeAndVote(stakeAddress: stakeAddress, pool: pool, drep: drep)
        case .registerAndDelegateStake: .registerAndDelegateStake(stakeAddress: stakeAddress, pool: pool)
        case .registerAndDelegateVote: .registerAndDelegateVote(stakeAddress: stakeAddress, drep: drep)
        case .registerAndDelegateStakeAndVote: .registerAndDelegateStakeAndVote(stakeAddress: stakeAddress, pool: pool, drep: drep)
        case .registerPool: .registerPool(poolDraft)
        case .retirePool: .retirePool(pool: pool, epoch: epoch)
        case .registerDRep: .registerDRep(keyHash: keyHash, anchorURL: anchorURL, anchorHash: anchorHash)
        case .unregisterDRep: .unregisterDRep(keyHash: keyHash)
        case .updateDRep: .updateDRep(keyHash: keyHash, anchorURL: anchorURL, anchorHash: anchorHash)
        case .authorizeCommitteeHot: .authorizeCommitteeHot(coldKey: keyHash, hotKey: hotKey)
        case .resignCommitteeCold: .resignCommitteeCold(coldKey: keyHash, anchorURL: anchorURL, anchorHash: anchorHash)
        }
    }
}
