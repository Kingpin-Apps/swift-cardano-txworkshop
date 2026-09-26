import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// Readable names for native assets, from the transaction's own CIP-25
/// metadata and from the token registry.
struct AssetNames {
    private var names: [String: AssetName] = [:]

    struct AssetName {
        let name: String
        let source: AssetDetail.NameSource
        var ticker: String?
        var decimals: Int?
    }

    init(metadata: [UInt64: TransactionMetadatum], registry: [TokenInfo]) {
        for token in registry {
            guard let name = token.name ?? token.ticker else { continue }
            names[token.subject] = AssetName(name: name, source: .registry, ticker: token.ticker, decimals: token.decimals)
        }
        // CIP-25 wins: it is what this transaction says about its own assets.
        if let nft = metadata[721] {
            for (subject, name) in Self.cip25Names(nft) {
                names[subject] = AssetName(name: name, source: .cip25)
            }
        }
    }

    subscript(subject: String) -> AssetName? { names[subject] }

    /// `{policy: {asset name: {"name": …}}}` under label 721. Version 1 keys
    /// are text (the policy in hex, the asset name as UTF-8); version 2 keys
    /// are bytes.
    static func cip25Names(_ value: TransactionMetadatum) -> [String: String] {
        guard case .map(let policies) = value else { return [:] }
        var names: [String: String] = [:]
        for (policyKey, assets) in policies {
            let policy: String
            switch policyKey {
            case .text(let text) where text.count == 56: policy = text.lowercased()
            case .bytes(let bytes) where bytes.count == 28: policy = bytes.hex
            default: continue
            }
            guard case .map(let assets) = assets else { continue }
            for (assetKey, fields) in assets {
                let assetHex: String
                switch assetKey {
                case .text(let text): assetHex = Data(text.utf8).hex
                case .bytes(let bytes): assetHex = bytes.hex
                default: continue
                }
                guard case .map(let fields) = fields, let name = fields[.text("name")].flatMap(text) else { continue }
                names[policy + assetHex] = name
            }
        }
        return names
    }

    /// Text, or text split into a list of chunks as CIP-25 allows.
    private static func text(_ value: TransactionMetadatum) -> String? {
        switch value {
        case .text(let text): return text
        case .list(let parts):
            let chunks = parts.compactMap { part -> String? in
                if case .text(let text) = part { return text }
                return nil
            }
            return chunks.count == parts.count && !chunks.isEmpty ? chunks.joined() : nil
        default: return nil
        }
    }
}
