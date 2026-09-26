import Foundation
import TxWorkshopCore

/// What only the Developer ID build can do: reach a local cardano-node over
/// its socket and run cardano-cli, which the App Sandbox does not allow.
///
/// Linked only by the direct macOS app target, so none of it is in the App
/// Store build.
public enum DirectDistribution {
    /// The provider kinds this build adds.
    public static let providerKinds: [ProviderKind] = ProviderKind.allCases.filter(\.requiresDirectDistribution)

    /// Where a local node usually puts its socket.
    public static let defaultSocketPaths = [
        "~/cardano/node.socket",
        "~/.cardano/node.socket",
        "/opt/cardano/ipc/node.socket",
    ]
}
