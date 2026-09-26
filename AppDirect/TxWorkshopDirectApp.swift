import SwiftUI
import TxWorkshopDirect
import TxWorkshopUI

/// The Developer ID build: outside the App Sandbox, so it may reach a local
/// node and run cardano-cli. Built with `DIRECT_DISTRIBUTION`.
@main
struct TxWorkshopDirectApp: App {
    var body: some Scene {
        #if DIRECT_DISTRIBUTION
        TxWorkshopScenes(directDistribution: !DirectDistribution.providerKinds.isEmpty)
        #else
        TxWorkshopScenes()
        #endif
    }
}
