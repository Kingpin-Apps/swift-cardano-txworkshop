import SwiftUI
import TxWorkshopCore

/// The app's scenes: a document group, plus a Settings window on macOS.
/// The app targets wrap this in their `@main` type.
public struct TxWorkshopScenes: Scene {
    @State private var providers: ProviderSettingsStore
    @State private var signingKeys = SigningKeyStore()
    @State private var tracker = SubmissionTracker()
    @State private var hardwareAccounts = HardwareAccountStore()

    /// - Parameter directDistribution: Whether this is the Developer ID build,
    ///   which may offer providers the App Sandbox rules out.
    public init(directDistribution: Bool = false) {
        providers = ProviderSettingsStore(directDistribution: directDistribution)
    }

    public var body: some Scene {
        DocumentGroup { document in
            DocumentShell(document: document)
                .environment(providers)
                .environment(signingKeys)
                .environment(tracker)
                .environment(hardwareAccounts)
                .task { tracker.start() }
        } makeDocument: { _, _ in
            TxWorkshopDocument()
        }

        #if os(macOS)
        Settings {
            ProviderSettingsView()
                .environment(providers)
                .frame(minWidth: 520, minHeight: 360)
        }
        #endif
    }
}
