import Foundation
import Security
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

    /// Whether this build is signed for iCloud key-value storage: the
    /// released Developer ID build, with its provisioning profile. A local
    /// Debug build, signed ad hoc, is not, and keeps its settings on the Mac.
    public static var hasICloud: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, nil) != nil
    }
}
