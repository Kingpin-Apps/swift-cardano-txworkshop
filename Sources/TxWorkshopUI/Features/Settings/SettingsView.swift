import SwiftUI
import TxWorkshopCore

/// The app's settings: appearance and chain data providers. A Settings
/// window with tabs on macOS; a sheet elsewhere, which on visionOS is just
/// the providers.
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        #if os(macOS)
        TabView {
            Tab {
                Form { AppearanceSection() }
                    .formStyle(.grouped)
                    .twScreenBackground()
            } label: {
                Label {
                    Text("General", bundle: #bundle)
                } icon: {
                    Image(systemName: "gearshape")
                }
            }
            Tab {
                ProviderSettingsView()
            } label: {
                Label {
                    Text("Providers", bundle: #bundle)
                } icon: {
                    Image(systemName: "network")
                }
            }
        }
        #elseif os(visionOS)
        // visionOS has no light or dark appearance to choose, so the only
        // settings are the providers.
        NavigationStack {
            ProviderSettingsView(showsDone: false)
                .twSheetRoot()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
        #else
        NavigationStack {
            Form {
                AppearanceSection()
                Section {
                    NavigationLink {
                        ProviderSettingsView(showsDone: false)
                    } label: {
                        Label {
                            Text("Providers", bundle: #bundle)
                        } icon: {
                            Image(systemName: "network")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .twScreenBackground()
            .navigationTitle(Text("Settings", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        #endif
    }
}

/// Light, dark, or whatever the system uses.
struct AppearanceSection: View {
    @AppStorage(TWAppearance.storageKey) private var appearance = TWAppearance.system

    var body: some View {
        Section {
            Picker(selection: $appearance) {
                ForEach(TWAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Text("Appearance", bundle: #bundle)
            }
            .pickerStyle(.segmented)
        } header: {
            #if !os(macOS)
            Text("Appearance", bundle: #bundle)
            #endif
        } footer: {
            Text("System follows your device's light or dark setting.", bundle: #bundle)
        }
    }
}

#Preview {
    SettingsView()
        .environment(ProviderSettingsStore.preview)
        .twWindowStyle()
}
