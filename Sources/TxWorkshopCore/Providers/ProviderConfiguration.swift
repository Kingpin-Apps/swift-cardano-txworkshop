import Foundation

/// A kind of chain data provider.
public enum ProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case blockfrost
    case koios
    /// Ogmios, optionally with a Kupo index beside it.
    case ogmios
    /// A Yaci DevKit devnet.
    case yaciDevKit
    /// A local cardano-node over its socket. Developer ID build only.
    case localNode
    /// No provider: everything comes from the document or is typed in.
    case offline

    public var id: String { rawValue }

    public var name: LocalizedStringResource {
        switch self {
        case .blockfrost: LocalizedStringResource("Blockfrost", bundle: #bundle)
        case .koios: LocalizedStringResource("Koios", bundle: #bundle)
        case .ogmios: LocalizedStringResource("Ogmios", bundle: #bundle)
        case .yaciDevKit: LocalizedStringResource("Yaci DevKit", bundle: #bundle)
        case .localNode: LocalizedStringResource("Local node", bundle: #bundle)
        case .offline: LocalizedStringResource("Offline", bundle: #bundle)
        }
    }

    /// Whether the provider needs an API key.
    public var requiresAPIKey: Bool { self == .blockfrost }

    /// Whether the provider accepts an optional API key.
    public var acceptsAPIKey: Bool { self == .blockfrost || self == .koios }

    /// Whether the provider is reached at a URL the person gives.
    public var needsURL: Bool { self == .ogmios || self == .yaciDevKit }

    /// Whether only the Developer ID build can use the provider: it needs a
    /// socket or a process the App Sandbox does not allow.
    public var requiresDirectDistribution: Bool { self == .localNode }

    /// The kinds available in a build.
    public static func available(directDistribution: Bool) -> [ProviderKind] {
        allCases.filter { directDistribution || !$0.requiresDirectDistribution }
    }
}

/// A configured provider for one network. Its API key, if any, is kept in the
/// Keychain under ``id``, never here.
public struct ProviderConfiguration: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: ProviderKind
    public var network: CardanoNetwork
    /// The server URL, for providers reached at one; otherwise the provider's
    /// public endpoint for the network is used.
    public var url: URL?
    /// A Kupo index to use with Ogmios.
    public var kupoURL: URL?
    /// The path of a local node's socket (Developer ID build only).
    public var socketPath: String?

    public init(
        id: UUID = UUID(), name: String, kind: ProviderKind, network: CardanoNetwork,
        url: URL? = nil, kupoURL: URL? = nil, socketPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.network = network
        self.url = url
        self.kupoURL = kupoURL
        self.socketPath = socketPath
    }

    /// The Keychain account the provider's API key is stored under.
    public var secretAccount: String { "provider-\(id.uuidString)" }

    /// Why the configuration cannot be used yet, if it cannot.
    public func problem(hasAPIKey: Bool) -> LocalizedStringResource? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return LocalizedStringResource("Give the provider a name.", bundle: #bundle)
        }
        if kind.requiresAPIKey && !hasAPIKey {
            return LocalizedStringResource("Add the provider's API key.", bundle: #bundle)
        }
        if kind.needsURL && url == nil {
            return LocalizedStringResource("Add the server URL.", bundle: #bundle)
        }
        if kind == .localNode && (socketPath ?? "").isEmpty {
            return LocalizedStringResource("Choose the node's socket.", bundle: #bundle)
        }
        return nil
    }
}
