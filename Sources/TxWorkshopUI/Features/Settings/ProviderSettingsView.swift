import SwiftUI
import TxWorkshopCore

/// The configured chain data providers, per network.
public struct ProviderSettingsView: View {
    @Environment(ProviderSettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ProviderConfiguration?
    @State private var showsOnboarding = false
    /// Whether to offer Done, when this is the root of a sheet.
    private let showsDone: Bool

    public init(showsDone: Bool = true) {
        self.showsDone = showsDone
    }

    public var body: some View {
        Form {
            if store.providers.isEmpty {
                Section {
                    Button {
                        showsOnboarding = true
                    } label: {
                        Text("Help Me Choose a Provider…", bundle: #bundle)
                    }
                } footer: {
                    Text("Koios is free with no sign-up; the guide also shows how to set up Blockfrost, Ogmios and the others.", bundle: #bundle)
                }
            }
            ForEach(CardanoNetwork.allCases) { network in
                Section {
                    let providers = store.providers(for: network)
                    if providers.isEmpty {
                        Text("No provider. Transactions on \(Text(network.name)) can only be inspected offline.", bundle: #bundle)
                            .foregroundStyle(TWColor.secondaryText)
                    }
                    ForEach(providers) { provider in
                        ProviderRow(
                            provider: provider,
                            isSelected: store.selectedProvider(for: network)?.id == provider.id,
                            select: { store.select(provider) },
                            edit: { editing = provider }
                        )
                    }
                    Button {
                        editing = ProviderConfiguration(name: "", kind: .blockfrost, network: network)
                    } label: {
                        Label {
                            Text("Add Provider", bundle: #bundle)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                } header: {
                    Text(network.name)
                }
            }
            if let error = store.lastError {
                Section {
                    TWErrorText(error)
                }
            }
        }
        .formStyle(.grouped)
        .twScreenBackground()
        .navigationTitle(Text("Providers", bundle: #bundle))
        #if !os(macOS)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: #bundle)
                    }
                }
            }
        }
        #endif
        .sheet(isPresented: $showsOnboarding) {
            ProviderOnboardingView()
        }
        .sheet(item: $editing) { provider in
            NavigationStack {
                ProviderEditor(provider: provider)
            }
        }
    }
}

#Preview {
    NavigationStack { ProviderSettingsView() }
        .environment(ProviderSettingsStore.preview)
}
