import SwiftUI
import TxWorkshopCore

/// Adds or edits one provider. The API key goes to the Keychain.
struct ProviderEditor: View {
    @Environment(ProviderSettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProviderConfiguration
    @State private var urlText: String
    @State private var kupoText: String
    @State private var apiKey: String
    @State private var socketPath: String
    @State private var cliPath: String

    init(provider: ProviderConfiguration) {
        draft = provider
        urlText = provider.url?.absoluteString ?? ""
        kupoText = provider.kupoURL?.absoluteString ?? ""
        apiKey = ""
        socketPath = provider.socketPath ?? ""
        cliPath = provider.cliPath ?? ""
    }

    /// Whether this adds a provider, rather than editing a saved one. A new
    /// one can arrive with its name filled in, from the provider set-up.
    private var isNew: Bool {
        !store.providers.contains { $0.id == draft.id }
    }

    var body: some View {
        Form {
            Section {
                TextField(text: $draft.name) { Text("Name", bundle: #bundle) }
                Picker(selection: $draft.kind) {
                    ForEach(store.availableKinds) { kind in
                        Text(kind.name).tag(kind)
                    }
                } label: {
                    Text("Kind", bundle: #bundle)
                }
                Picker(selection: $draft.network) {
                    ForEach(CardanoNetwork.allCases) { network in
                        Text(network.name).tag(network)
                    }
                } label: {
                    Text("Network", bundle: #bundle)
                }
            }
            if draft.kind.needsURL || draft.kind == .koios || draft.kind == .blockfrost {
                Section {
                    TextField(text: $urlText) {
                        Text(draft.kind.needsURL ? "Server URL" : "Custom URL (optional)", bundle: #bundle)
                    }
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    if draft.kind == .ogmios {
                        TextField(text: $kupoText) { Text("Kupo URL (optional)", bundle: #bundle) }
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                    }
                }
            }
            if draft.kind.needsSocket {
                Section {
                    TextField(text: $socketPath) {
                        Text("Node socket path", bundle: #bundle)
                    }
                    .autocorrectionDisabled()
                    if draft.kind == .cardanoCLI {
                        TextField(text: $cliPath, prompt: Text(verbatim: configured.resolvedCLIPath ?? "cardano-cli")) {
                            Text("cardano-cli path", bundle: #bundle)
                        }
                        .autocorrectionDisabled()
                    }
                } footer: {
                    if draft.kind == .cardanoCLI {
                        Text("Left empty, cardano-cli is looked for in Homebrew, /usr/local/bin, ~/.local/bin, ~/cardano/bin and the node releases in ~/cardano.", bundle: #bundle)
                    } else {
                        Text("The node's socket, as in its --socket-path, for example ~/cardano/node.socket.", bundle: #bundle)
                    }
                }
            }
            if draft.kind.acceptsAPIKey {
                Section {
                    SecureField(text: $apiKey) {
                        Text(store.hasAPIKey(draft) ? "Replace API key" : "API key", bundle: #bundle)
                    }
                } footer: {
                    Text("Kept in your Keychain, on this device only.", bundle: #bundle)
                }
            }
            if !isNew {
                Section {
                    Button(role: .destructive) {
                        store.remove(draft)
                        dismiss()
                    } label: {
                        Text("Remove Provider", bundle: #bundle)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? Text("New Provider", bundle: #bundle) : Text(verbatim: draft.name))
        .twSheetRoot()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: #bundle) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    store.save(configured, apiKey: apiKey.isEmpty ? nil : apiKey)
                    dismiss()
                } label: {
                    Text("Save", bundle: #bundle)
                }
                .disabled(problem != nil)
            }
        }
    }

    private var configured: ProviderConfiguration {
        var provider = draft
        provider.url = URL(string: urlText.trimmingCharacters(in: .whitespaces)).flatMap { $0.scheme == nil ? nil : $0 }
        provider.kupoURL = URL(string: kupoText.trimmingCharacters(in: .whitespaces)).flatMap { $0.scheme == nil ? nil : $0 }
        provider.socketPath = socketPath.isEmpty ? nil : socketPath
        provider.cliPath = cliPath.isEmpty ? nil : cliPath
        return provider
    }

    private var problem: LocalizedStringResource? {
        configured.problem(hasAPIKey: !apiKey.isEmpty || store.hasAPIKey(draft))
    }
}
