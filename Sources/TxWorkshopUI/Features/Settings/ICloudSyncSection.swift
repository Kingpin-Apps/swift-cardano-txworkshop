import SwiftUI
import TxWorkshopCore

/// The choice to sync settings through iCloud, in Settings and in the provider
/// set-up. Hidden in the Developer ID build, which has no iCloud.
struct ICloudSyncSection: View {
    @Environment(ProviderSettingsStore.self) private var store

    var body: some View {
        if store.canSyncWithICloud {
            Section {
                Toggle(isOn: Binding(get: { store.syncsWithICloud }, set: { store.setSyncsWithICloud($0) })) {
                    Label {
                        Text("Sync with iCloud", bundle: #bundle)
                    } icon: {
                        Image(systemName: "icloud")
                    }
                }
                .accessibilityIdentifier("syncWithICloud")
            } footer: {
                VStack(alignment: .leading, spacing: TWSpacing.xs) {
                    Text("Keeps your providers, their API keys and your block explorer the same on your iPhone, iPad, Mac and Apple Vision Pro. API keys go in iCloud Keychain, end-to-end encrypted. Signing keys never leave this device.", bundle: #bundle)
                    if store.syncsWithICloud && !store.iCloudAvailable {
                        Text("Sign in to iCloud on this device to sync; until then, settings stay here.", bundle: #bundle)
                            .foregroundStyle(TWColor.warning)
                    }
                }
            }
        }
    }
}
