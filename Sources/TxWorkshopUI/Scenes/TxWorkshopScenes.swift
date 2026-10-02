import SwiftUI
import SwiftCardanoExplorers
import TxWorkshopCore

/// The app's scenes: a launch screen on iPhone, iPad and visionOS, a
/// document group, and a Settings window on macOS.
/// The app targets wrap this in their `@main` type.
public struct TxWorkshopScenes: Scene {
    @State private var providers: ProviderSettingsStore
    @State private var signingKeys = SigningKeyStore()
    @State private var tracker = SubmissionTracker()
    @State private var hardwareAccounts = HardwareAccountStore()
    /// Keeps the chosen explorer the same on every device (App Store build).
    @State private var settingsMirror: ICloudSettingsMirror?

    /// - Parameter directDistribution: Whether this is the Developer ID build,
    ///   which may offer providers the App Sandbox rules out. The App Store
    ///   build syncs providers, their API keys and the explorer through iCloud;
    ///   the Developer ID build has no iCloud and keeps them on the Mac.
    public init(directDistribution: Bool = false) {
        if directDistribution {
            providers = ProviderSettingsStore(directDistribution: true)
        } else {
            providers = .syncingWithICloud()
            let mirror = ICloudSettingsMirror(keys: [BlockchainExplorer.storageKey])
            mirror.start()
            settingsMirror = mirror
        }
    }

    public var body: some Scene {
        #if os(iOS) || os(visionOS)
        DocumentGroupLaunchScene(LocalizedStringResource("Cardano TxWorkshop", bundle: #bundle)) {
            NewDocumentButton(LocalizedStringResource("New Transaction", bundle: #bundle))
        } background: {
            // Also applies the chosen appearance before any document opens.
            TWColor.background
                .ignoresSafeArea()
                .twWindowStyle()
        }
        #endif

        DocumentGroup { document in
            DocumentShell(document: document)
                .environment(providers)
                .environment(signingKeys)
                .environment(tracker)
                .environment(hardwareAccounts)
                .twWindowStyle()
                .task {
                    tracker.start()
                }
        } makeDocument: { _, _ in
            TxWorkshopDocument()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(providers)
                .frame(minWidth: 520, minHeight: 360)
                .twWindowStyle()
        }
        #endif
    }
}
