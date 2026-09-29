import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import TxWorkshopCore
#if os(macOS)
import SystemPackage
#endif

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
            #if os(macOS)
            return NodeSocketChainContext(socketPath: FilePath(try socket(of: provider)), network: network)
            #else
            throw ChainContextFactoryError.needsDirectDistribution
            #endif
        case .cardanoCLI:
            #if os(macOS)
            guard let cli = provider.resolvedCLIPath else {
                throw ChainContextFactoryError.misconfigured("cardano-cli was not found. Give its path in the provider's settings.")
            }
            return CardanoCLIChainContext(cli: cli, socketPath: try socket(of: provider), network: provider.network)
            #else
            throw ChainContextFactoryError.needsDirectDistribution
            #endif
        case .offline:
            throw ChainContextFactoryError.offline
        }
    }

    /// The node socket a provider names, which a running node must be answering.
    private func socket(of provider: ProviderConfiguration) throws -> String {
        guard let path = provider.socketPath.map(ProviderConfiguration.expandingTilde), !path.isEmpty else {
            throw ChainContextFactoryError.misconfigured("Give the node's socket path.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw ChainContextFactoryError.misconfigured(
                "There is no node socket at \(path). Start cardano-node, or check the socket path in the provider's settings.")
        }
        #if os(macOS)
        // A node that has stopped leaves its socket file behind, and connecting
        // to it then fails with a bare "connection refused".
        switch Self.probe(socket: path) {
        case .answering:
            break
        case .refused:
            throw ChainContextFactoryError.misconfigured(
                "cardano-node is not answering at \(path). Is it running? Start it, or check the socket path in the provider's settings.")
        case .notPermitted:
            throw ChainContextFactoryError.misconfigured("The app may not open the node socket at \(path). Check its permissions.")
        }
        #endif
        return path
    }

    #if os(macOS)
    enum SocketProbe: Equatable { case answering, refused, notPermitted }

    /// Whether something is listening on the Unix socket at `path`.
    static func probe(socket path: String) -> SocketProbe {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .refused }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return .refused }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected == 0 { return .answering }
        return errno == EACCES || errno == EPERM ? .notPermitted : .refused
    }
    #endif
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
