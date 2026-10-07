import Foundation
import SwiftCardanoCIP21

// CIP-21's rules live in swift-cardano-cips, where the transaction builder
// uses them too. These names keep the app's views off that package.
public typealias CIP21Report = SwiftCardanoCIP21.CIP21Report
public typealias CIP21Finding = SwiftCardanoCIP21.CIP21Finding
public typealias CIP21SigningMode = SwiftCardanoCIP21.CIP21SigningMode

public enum CIP21Check {
    /// What CIP-21 asks of `bytes`, a whole transaction, for hardware wallets
    /// to sign it.
    public static func report(_ bytes: Data) throws -> CIP21Report {
        try CIP21.report(bytes)
    }
}
