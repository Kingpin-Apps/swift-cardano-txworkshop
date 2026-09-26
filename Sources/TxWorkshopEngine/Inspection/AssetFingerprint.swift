import Foundation
import SwiftCardanoCore
import SwiftNaCl

/// CIP-14 asset fingerprints: `asset1…`, the bech32 of the Blake2b-160 hash
/// of the policy id and asset name.
public enum AssetFingerprint {
    public static func fingerprint(policyID: Data, assetName: Data) -> String? {
        guard let hash = try? Hash().blake2b(data: policyID + assetName, digestSize: 20, encoder: RawEncoder.self) else {
            return nil
        }
        return Bech32().encode(hrp: "asset", witprog: hash)
    }
}
