import SwiftUI
import TxWorkshopCore

/// The choice to sync settings through iCloud, in Settings and in the provider
/// set-up. A build not signed for iCloud, such as one signed ad hoc, says so
/// instead: it cannot sync, nor read the API keys a signed build keeps.
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
        } else {
            Section {
                Label {
                    Text("This build is not signed for iCloud, so it cannot sync. Its settings and API keys stay with it, and it cannot read the API keys the downloaded app keeps.", bundle: #bundle)
                } icon: {
                    Image(systemName: "icloud.slash")
                }
                .accessibilityIdentifier("iCloudUnavailable")
            } footer: {
                Text("The App Store and downloaded apps sync, as does a build signed with the team.", bundle: #bundle)
            }
        }
    }
}
