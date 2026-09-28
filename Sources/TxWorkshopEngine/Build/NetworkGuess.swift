import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// What something says about the network it belongs to. An address only
/// tells mainnet from testnet; a file name may say which testnet.
public enum NetworkHint: Sendable, Equatable {
    /// This network, for certain or as the file name says.
    case network(CardanoNetwork)
    /// A testnet, but not which one.
    case testnet

    /// The networks it could be.
    public var candidates: [CardanoNetwork] {
        switch self {
        case .network(let network): [network]
        case .testnet: [.preprod, .preview]
        }
    }

    /// Whether `network` fits the hint.
    public func allows(_ network: CardanoNetwork) -> Bool {
        switch self {
        case .network(let expected): network == expected
        case .testnet: network != .mainnet
        }
    }
}

public enum NetworkGuess {
    /// The network an address's network id points to, sharpened by a file
    /// name such as `alice.preview.addr`.
    public static func hint(for id: NetworkId, fileName: String? = nil) -> NetworkHint {
        if id == .mainnet { return .network(.mainnet) }
        if let fileName, let named = network(inFileName: fileName), named != .mainnet { return .network(named) }
        return .testnet
    }

    /// A network named in a file name: `preview`, `preprod` or `mainnet`.
    public static func network(inFileName name: String) -> CardanoNetwork? {
        let name = name.lowercased()
        if name.contains("preview") { return .preview }
        if name.contains("preprod") { return .preprod }
        if name.contains("mainnet") { return .mainnet }
        return nil
    }

    /// What a value read for the builder says about its network: the
    /// network of an address in it, when it holds one.
    public static func hint(for kind: ValueKind, text: String, fileName: String? = nil) -> NetworkHint? {
        guard kind == .address || kind == .stakeAddress || kind == .keyHash else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (address, _) = try? ValueReader.parseAddress(text), address.addressType?.rawValue != 8 else { return nil }
        return hint(for: address.network, fileName: fileName)
    }

    /// What a transaction says about its network: its body's network id, or
    /// else the network of its outputs.
    public static func hint(forTransaction bytes: Data) -> NetworkHint? {
        guard let transaction = try? Transaction.fromCBOR(data: bytes) else { return nil }
        let body = transaction.transactionBody
        if let id = body.networkId, let networkID = NetworkId(rawValue: id) {
            return hint(for: networkID)
        }
        let networks = Set(body.outputs.compactMap { output -> NetworkId? in
            output.address.addressType?.rawValue == 8 ? nil : output.address.network
        })
        guard networks.count == 1, let id = networks.first else { return nil }
        return hint(for: id)
    }
}
