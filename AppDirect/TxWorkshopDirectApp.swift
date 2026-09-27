import Sparkle
import SwiftUI
import TxWorkshopDirect
import TxWorkshopUI

/// The Developer ID build: outside the App Sandbox, so it may reach a local
/// node and run cardano-cli. Built with `DIRECT_DISTRIBUTION`. Updates come
/// through Sparkle from the public releases repository.
@main
struct TxWorkshopDirectApp: App {
    /// Starts checking for updates only once the release key is set, so a
    /// build without one never fetches an appcast it cannot verify.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: !(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty,
        updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        scenes
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") { updater.checkForUpdates(nil) }
                        .disabled(!updater.updater.canCheckForUpdates)
                }
            }
    }

    private var scenes: TxWorkshopScenes {
        #if DIRECT_DISTRIBUTION
        TxWorkshopScenes(directDistribution: !DirectDistribution.providerKinds.isEmpty)
        #else
        TxWorkshopScenes()
        #endif
    }
}
