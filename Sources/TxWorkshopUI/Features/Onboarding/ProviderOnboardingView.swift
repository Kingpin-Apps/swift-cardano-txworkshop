import SwiftUI
import TxWorkshopCore

/// First-run setup: explains what a chain data provider is for and helps add
/// one. Koios is one tap; the others open the provider editor filled in as far
/// as it can be, with a line on how to get what it asks for.
public struct ProviderOnboardingView: View {
    @Environment(ProviderSettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var koiosNetworks: Set<CardanoNetwork> = [.mainnet]
    @State private var editing: ProviderConfiguration?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Cardano TxWorkshop reads the chain through a provider: to look up the outputs a transaction spends, fetch the protocol parameters and ledger state for validating, and submit. Without one you can still open, inspect and edit transactions offline.", bundle: #bundle)
                }

                // Asked first, so providers already set up on another device
                // arrive before any are added here.
                ICloudSyncSection()

                if !store.providers.isEmpty {
                    Section {
                        ForEach(store.providers) { provider in
                            Label {
                                Text("\(provider.name) on \(Text(provider.network.name))", bundle: #bundle)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            .labelStyle(.status(TWColor.success))
                        }
                    } header: {
                        Text("Added", bundle: #bundle)
                    } footer: {
                        Text("Add more, or change them, any time in Settings › Providers.", bundle: #bundle)
                    }
                }

                Section {
                    ForEach(CardanoNetwork.allCases) { network in
                        Toggle(isOn: binding(for: network)) { Text(network.name) }
                    }
                    Button(action: addKoios) {
                        Text("Use Koios", bundle: #bundle)
                    }
                    .disabled(koiosNetworks.isEmpty)
                    Link(destination: URL(string: "https://koios.rest")!) {
                        Text("Learn More", bundle: #bundle)
                    }
                } header: {
                    Text("Quick start: Koios", bundle: #bundle)
                } footer: {
                    Text("Free, with no sign-up. Koios's public service is rate limited, so heavy use can be slowed or refused; a free Koios account gives a token with higher limits, which you can add later as the provider's API key.", bundle: #bundle)
                }

                Section {
                    ForEach(Self.guides.filter { store.availableKinds.contains($0.kind) }, id: \.kind) { guide in
                        VStack(alignment: .leading, spacing: TWSpacing.xs) {
                            Text(guide.kind.name).font(.headline)
                            Text(guide.summary)
                                .font(.callout)
                                .foregroundStyle(TWColor.secondaryText)
                            HStack {
                                Button {
                                    editing = guide.draft(on: .mainnet)
                                } label: {
                                    Text("Set Up…", bundle: #bundle)
                                }
                                .buttonStyle(.bordered)
                                if let link = guide.link {
                                    Link(destination: link) {
                                        Text("Learn More", bundle: #bundle)
                                    }
                                    // Two buttons in one row: without this, a tap
                                    // anywhere in the row fires both.
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.top, TWSpacing.xxs)
                        }
                        .padding(.vertical, TWSpacing.xs)
                    }
                } header: {
                    Text("Other providers", bundle: #bundle)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Connect to Cardano", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if store.providers.isEmpty {
                        Button { dismiss() } label: { Text("Skip for Now", bundle: #bundle) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !store.providers.isEmpty {
                        Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                    }
                }
            }
            .sheet(item: $editing) { provider in
                NavigationStack {
                    ProviderEditor(provider: provider)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    private func binding(for network: CardanoNetwork) -> Binding<Bool> {
        Binding(
            get: { koiosNetworks.contains(network) },
            set: { isOn in
                if isOn { koiosNetworks.insert(network) } else { koiosNetworks.remove(network) }
            }
        )
    }

    /// Adds Koios for each chosen network that does not have it already.
    private func addKoios() {
        for network in CardanoNetwork.allCases where koiosNetworks.contains(network) {
            guard !store.providers(for: network).contains(where: { $0.kind == .koios }) else { continue }
            store.save(ProviderConfiguration(name: "Koios", kind: .koios, network: network))
        }
    }
}

extension ProviderOnboardingView {
    /// How to get started with one kind of provider.
    struct Guide {
        let kind: ProviderKind
        let summary: LocalizedStringResource
        let link: URL?
        /// A URL to fill in for the person, where there is a usual one.
        var defaultURL: URL?

        func draft(on network: CardanoNetwork) -> ProviderConfiguration {
            ProviderConfiguration(name: String(localized: kind.name), kind: kind, network: network, url: defaultURL)
        }
    }

    static let guides: [Guide] = [
        Guide(
            kind: .blockfrost,
            summary: LocalizedStringResource("A hosted API with a free plan. Sign up at blockfrost.io, create a project for each network, and paste its project ID as the API key.", bundle: #bundle),
            link: URL(string: "https://blockfrost.io")
        ),
        Guide(
            kind: .ogmios,
            summary: LocalizedStringResource("Your own node's Ogmios server, or a hosted one such as Demeter. Give its URL, and a Kupo URL beside it to look up outputs by address.", bundle: #bundle),
            link: URL(string: "https://ogmios.dev")
        ),
        Guide(
            kind: .yaciDevKit,
            summary: LocalizedStringResource("A local devnet for testing, with instant blocks and test funds. Start it with Docker; its store answers at `http://localhost:8080`.", bundle: #bundle),
            link: URL(string: "https://devkit.yaci.xyz"),
            defaultURL: URL(string: "http://localhost:8080")
        ),
        Guide(
            kind: .localNode,
            summary: LocalizedStringResource("Your own cardano-node on this Mac, read through its socket. Give the socket path, as in the node's --socket-path.", bundle: #bundle),
            link: URL(string: "https://developers.cardano.org/docs/get-started/cardano-node/installing-cardano-node")
        ),
        Guide(
            kind: .cardanoCLI,
            summary: LocalizedStringResource("cardano-cli querying your own node. Give the node's socket path; cardano-cli is found where it is usually installed.", bundle: #bundle),
            link: URL(string: "https://developers.cardano.org/docs/get-started/cardano-cli/")
        ),
    ]
}

/// Shows the provider set-up once, the first time a document opens with no
/// provider configured.
struct ProviderOnboardingPresenter: ViewModifier {
    @Environment(ProviderSettingsStore.self) private var store
    @AppStorage("providerOnboardingShown") private var shown = false
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !shown && store.providers.isEmpty { isPresented = true }
            }
            .sheet(isPresented: $isPresented, onDismiss: { shown = true }) {
                ProviderOnboardingView()
                    .twWindowStyle()
            }
    }
}

#Preview {
    ProviderOnboardingView()
        .environment(ProviderSettingsStore.preview)
}
