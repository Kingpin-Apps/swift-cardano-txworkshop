import SwiftUI
import TxWorkshopCore

/// One certificate: its kind, then the fields that kind needs.
struct CertificateDraftSection: View {
    @Binding var item: CertificateItem
    let onRemove: () -> Void
    @State private var kind = Kind.registerStake
    @State private var stakeAddress = ""
    @State private var target = ""
    @State private var keyHash = ""
    @State private var anchorURL = ""
    @State private var anchorHash = ""

    enum Kind: Hashable, CaseIterable {
        case registerStake, deregisterStake, delegateStake, delegateVote, registerDRep, unregisterDRep, updateDRep
    }

    var body: some View {
        Section {
            Picker(selection: $kind) {
                Text("Register stake address", bundle: #bundle).tag(Kind.registerStake)
                Text("Deregister stake address", bundle: #bundle).tag(Kind.deregisterStake)
                Text("Delegate stake to a pool", bundle: #bundle).tag(Kind.delegateStake)
                Text("Delegate votes to a DRep", bundle: #bundle).tag(Kind.delegateVote)
                Text("Register as a DRep", bundle: #bundle).tag(Kind.registerDRep)
                Text("Retire as a DRep", bundle: #bundle).tag(Kind.unregisterDRep)
                Text("Update DRep metadata", bundle: #bundle).tag(Kind.updateDRep)
            } label: {
                Text("Certificate", bundle: #bundle)
            }
            switch kind {
            case .registerStake, .deregisterStake, .delegateStake, .delegateVote:
                ValueField(kind: .stakeAddress, text: $stakeAddress, prompt: Text("Stake address, key hash or stake key", bundle: #bundle))
                if kind == .delegateStake {
                    ValueField(kind: .pool, text: $target, prompt: Text("Pool id, hex, cold key or pool.json", bundle: #bundle))
                } else if kind == .delegateVote {
                    ValueField(kind: .drep, text: $target, prompt: Text("DRep id, key hash, key file, abstain or no-confidence", bundle: #bundle))
                }
            case .registerDRep, .unregisterDRep, .updateDRep:
                ValueField(kind: .drepKeyHash, text: $keyHash, prompt: Text("DRep id, key hash or DRep key file", bundle: #bundle))
                if kind != .unregisterDRep {
                    field($anchorURL, Text("Anchor URL (optional)", bundle: #bundle))
                    AnchorHashField(hash: $anchorHash, url: anchorURL, prompt: Text("Anchor hash (hex, or choose the anchor file)", bundle: #bundle))
                }
            }
        } header: {
            RemovableHeader(title: Text("Certificate", bundle: #bundle), onRemove: onRemove)
        } footer: {
            switch kind {
            case .registerStake, .registerDRep:
                Text("Pays the deposit the protocol parameters set.", bundle: #bundle)
            case .deregisterStake, .unregisterDRep:
                Text("Takes the deposit back.", bundle: #bundle)
            default:
                EmptyView()
            }
        }
        .onAppear(perform: load)
        .onChange(of: kind) { sync() }
        .onChange(of: stakeAddress) { sync() }
        .onChange(of: target) { sync() }
        .onChange(of: keyHash) { sync() }
        .onChange(of: anchorURL) { sync() }
        .onChange(of: anchorHash) { sync() }
    }

    private func field(_ text: Binding<String>, _ prompt: Text) -> some View {
        TextField(text: text) { prompt }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
    }

    private func load() {
        switch item.certificate {
        case .registerStake(let address): kind = .registerStake; stakeAddress = address
        case .deregisterStake(let address): kind = .deregisterStake; stakeAddress = address
        case .delegateStake(let address, let pool): kind = .delegateStake; stakeAddress = address; target = pool
        case .delegateVote(let address, let drep): kind = .delegateVote; stakeAddress = address; target = drep
        case .registerDRep(let hash, let url, let anchor): kind = .registerDRep; keyHash = hash; anchorURL = url; anchorHash = anchor
        case .unregisterDRep(let hash): kind = .unregisterDRep; keyHash = hash
        case .updateDRep(let hash, let url, let anchor): kind = .updateDRep; keyHash = hash; anchorURL = url; anchorHash = anchor
        }
    }

    private func sync() {
        item.certificate = switch kind {
        case .registerStake: .registerStake(stakeAddress: stakeAddress)
        case .deregisterStake: .deregisterStake(stakeAddress: stakeAddress)
        case .delegateStake: .delegateStake(stakeAddress: stakeAddress, pool: target)
        case .delegateVote: .delegateVote(stakeAddress: stakeAddress, drep: target)
        case .registerDRep: .registerDRep(keyHash: keyHash, anchorURL: anchorURL, anchorHash: anchorHash)
        case .unregisterDRep: .unregisterDRep(keyHash: keyHash)
        case .updateDRep: .updateDRep(keyHash: keyHash, anchorURL: anchorURL, anchorHash: anchorHash)
        }
    }
}
