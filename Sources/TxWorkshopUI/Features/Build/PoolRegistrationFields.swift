import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import UniformTypeIdentifiers

/// A stake pool's registration parameters: typed in, imported from a
/// pool.json, or fetched from the pool's registration on chain to edit and
/// register again as an update.
struct PoolRegistrationFields: View {
    @Binding var draft: PoolRegistrationDraft
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.documentNetwork) private var network
    @State private var isImporting = false
    @State private var isFetching = false
    @State private var notes: [String] = []
    @State private var problem: String?

    private var provider: ProviderConfiguration? {
        network.flatMap { providers.selectedProvider(for: $0) }
    }

    var body: some View {
        HStack {
            Button {
                isImporting = true
            } label: {
                Text("Import pool.json…", bundle: #bundle)
            }
            Spacer()
            Button(action: fetch) {
                Text("Fetch Registration", bundle: #bundle)
                    .opacity(isFetching ? 0 : 1)
                    .overlay { if isFetching { ProgressView() } }
            }
            .disabled(isFetching || provider == nil || draft.pool.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(Text("Fill the form from the pool's registration on chain, to edit and register again.", bundle: #bundle))
        }
        .buttonStyle(.borderless)
        ForEach(notes, id: \.self) { note in
            Label {
                Text(verbatim: note)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption)
            .labelStyle(.status(TWColor.warning))
        }
        if let problem { TWErrorText(problem) }

        Toggle(isOn: $draft.isUpdate) {
            Text("Already registered: update it, no deposit", bundle: #bundle)
        }
        ValueField(kind: .pool, text: $draft.pool, prompt: Text("Pool id, hex or cold key", bundle: #bundle))
        ValueField(kind: .vrfKeyHash, text: $draft.vrfKey, prompt: Text("VRF key hash or VRF key file", bundle: #bundle))
        TextField(value: $draft.pledge, format: .number) { Text("Pledge (lovelace)", bundle: #bundle) }
            .font(TWFont.figure)
        TextField(value: $draft.cost, format: .number) { Text("Fixed cost per epoch (lovelace)", bundle: #bundle) }
            .font(TWFont.figure)
        TextField(text: $draft.margin) { Text("Margin: 0.05, 5% or 1/20", bundle: #bundle) }
            .font(TWFont.figure)
            .autocorrectionDisabled()
        ValueField(kind: .stakeAddress, text: $draft.rewardAccount, prompt: Text("Reward account: stake address, key hash or stake key", bundle: #bundle))

        ForEach(draft.owners.indices, id: \.self) { index in
            HStack(alignment: .firstTextBaseline) {
                ValueField(kind: .stakeAddress, text: $draft.owners[index], prompt: Text("Owner: stake address, key hash or stake key", bundle: #bundle))
                removeButton { draft.owners.remove(at: index) }
            }
        }
        Button {
            draft.owners.append("")
        } label: {
            Label {
                Text("Add Owner", bundle: #bundle)
            } icon: {
                Image(systemName: "person.badge.plus")
            }
        }

        ForEach($draft.relays) { $relay in
            RelayRow(relay: $relay) { draft.relays.removeAll { $0.id == relay.id } }
        }
        Button {
            draft.relays.append(RelayDraft())
        } label: {
            Label {
                Text("Add Relay", bundle: #bundle)
            } icon: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
            }
        }

        TextField(text: $draft.metadataURL) { Text("Metadata URL (optional, at most 64 bytes)", bundle: #bundle) }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
        AnchorHashField(hash: $draft.metadataHash, url: draft.metadataURL, prompt: Text("Metadata hash (hex, or choose the metadata file)", bundle: #bundle))
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json, .data]) { result in
                if case .success(let url) = result { importPoolJSON(url) }
            }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label {
                Text("Remove", bundle: #bundle)
            } icon: {
                Image(systemName: "minus.circle")
            }
            .labelStyle(.iconOnly)
            .twHitTarget()
        }
        .buttonStyle(.borderless)
    }

    private func importPoolJSON(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try PoolRegistrationSource.poolJSON(Data(contentsOf: url), folder: url.deletingLastPathComponent())
            draft = imported.draft
            notes = imported.notes
            problem = nil
        } catch {
            problem = "\(url.lastPathComponent): \(error)"
        }
    }

    private func fetch() {
        guard let provider else { return }
        let pool = draft.pool
        let apiKey = providers.apiKey(for: provider)
        let network = network
        isFetching = true
        problem = nil
        Task {
            defer { isFetching = false }
            do {
                if let registered = try await PoolRegistrationSource.registered(pool, provider: provider, apiKey: apiKey, network: network) {
                    draft = registered
                    notes = []
                } else {
                    problem = String(localized: "\(provider.name) has no registration for this pool. Fill in the form to register it.", bundle: #bundle)
                }
            } catch {
                problem = String(describing: error)
            }
        }
    }
}

/// One relay: how it is reached, the host and the port.
private struct RelayRow: View {
    @Binding var relay: RelayDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            HStack {
                Picker(selection: $relay.kind) {
                    Text("IPv4", bundle: #bundle).tag(RelayDraft.Kind.ipv4)
                    Text("IPv6", bundle: #bundle).tag(RelayDraft.Kind.ipv6)
                    Text("DNS name", bundle: #bundle).tag(RelayDraft.Kind.dnsName)
                    Text("DNS SRV name", bundle: #bundle).tag(RelayDraft.Kind.srvName)
                } label: {
                    Text("Relay", bundle: #bundle)
                }
                Button(role: .destructive, action: onRemove) {
                    Label {
                        Text("Remove Relay", bundle: #bundle)
                    } icon: {
                        Image(systemName: "minus.circle")
                    }
                    .labelStyle(.iconOnly)
                    .twHitTarget()
                }
                .buttonStyle(.borderless)
            }
            HStack {
                TextField(text: $relay.host) {
                    relay.kind == .ipv4 || relay.kind == .ipv6
                        ? Text("Address", bundle: #bundle) : Text("Host name", bundle: #bundle)
                }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
                #endif
                if relay.kind != .srvName {
                    TextField(value: $relay.port, format: .number.grouping(.never)) { Text("Port", bundle: #bundle) }
                        .font(TWFont.figure)
                        .frame(maxWidth: 90)
                }
            }
        }
    }
}
