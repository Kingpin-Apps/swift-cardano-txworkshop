import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import TxWorkshopCore

public enum ChainContextFactoryError: Error, Sendable, Equatable, CustomStringConvertible {
    case offline
    case needsDirectDistribution
    case misconfigured(String)

    public var description: String {
        switch self {
        case .offline: "The offline provider does not connect to a chain."
        case .needsDirectDistribution: "This provider is only available in the Developer ID build."
        case .misconfigured(let reason): reason
        }
    }
}

/// Builds a live chain context for a configured provider.
public struct ChainContextFactory: Sendable {
    public init() {}

    public func makeContext(for provider: ProviderConfiguration, apiKey: String?) async throws -> any ChainContext {
        let network = provider.network.cardanoCoreNetwork
        switch provider.kind {
        case .blockfrost:
            guard let apiKey, !apiKey.isEmpty else { throw ChainContextFactoryError.misconfigured("Blockfrost needs an API key.") }
            return try await BlockFrostChainContext(projectId: apiKey, network: network, basePath: provider.url?.absoluteString)
        case .koios:
            return try await KoiosChainContext(apiKey: apiKey, network: network, basePath: provider.url?.absoluteString)
        case .ogmios:
            guard let url = provider.url, let host = url.host() else {
                throw ChainContextFactoryError.misconfigured("Ogmios needs a server URL.")
            }
            let secure = url.scheme == "https" || url.scheme == "wss"
            let ogmios = try await OgmiosChainContext(
                host: host,
                port: url.port ?? (secure ? 443 : 1337),
                path: url.path(),
                secure: secure,
                network: network
            )
            // Kupo answers UTxO lookups; everything else goes on to Ogmios.
            guard let kupoURL = provider.kupoURL else { return ogmios }
            return try KupoChainContext(url: kupoURL, network: network, wrapping: ogmios)
        case .yaciDevKit:
            guard let url = provider.url else { throw ChainContextFactoryError.misconfigured("Yaci DevKit needs a store URL.") }
            return try YaciDevkitChainContext(apiURL: url.absoluteString, network: network)
        case .localNode:
            throw ChainContextFactoryError.needsDirectDistribution
        case .offline:
            throw ChainContextFactoryError.offline
        }
    }
}

extension CardanoNetwork {
    /// The swift-cardano-core network value.
    public var cardanoCoreNetwork: SwiftCardanoCore.Network {
        switch self {
        case .mainnet: .mainnet
        case .preprod: .preprod
        case .preview: .preview
        case .custom(let magic): .custom(Int(magic))
        }
    }
}
