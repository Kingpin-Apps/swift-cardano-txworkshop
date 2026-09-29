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
    /// cardano-cli, querying a local node. Developer ID build only.
    case cardanoCLI
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
        case .cardanoCLI: LocalizedStringResource("cardano-cli", bundle: #bundle)
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
    public var requiresDirectDistribution: Bool { self == .localNode || self == .cardanoCLI }

    /// Whether the provider talks to a node's socket.
    public var needsSocket: Bool { self == .localNode || self == .cardanoCLI }

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
    /// The cardano-cli binary; when unset, the usual install places are
    /// searched (Developer ID build only).
    public var cliPath: String?

    public init(
        id: UUID = UUID(), name: String, kind: ProviderKind, network: CardanoNetwork,
        url: URL? = nil, kupoURL: URL? = nil, socketPath: String? = nil, cliPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.network = network
        self.url = url
        self.kupoURL = kupoURL
        self.socketPath = socketPath
        self.cliPath = cliPath
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
        if kind.needsSocket && (socketPath ?? "").isEmpty {
            return LocalizedStringResource("Choose the node's socket.", bundle: #bundle)
        }
        return nil
    }
}

extension ProviderConfiguration {
    /// Where cardano-cli is usually installed. A Mac app does not get the
    /// shell's PATH, so these are searched instead.
    public static let cliSearchPaths = [
        "/opt/homebrew/bin/cardano-cli",
        "/usr/local/bin/cardano-cli",
        "~/.local/bin/cardano-cli",
        "~/cardano/bin/cardano-cli",
    ]

    /// A path with a leading `~` made absolute.
    public static func expandingTilde(_ path: String) -> String {
        let path = path.trimmingCharacters(in: .whitespaces)
        guard path.hasPrefix("~") else { return path }
        return NSHomeDirectory() + "/" + path.dropFirst().drop { $0 == "/" }
    }

    /// The cardano-cli to run: the one given, or the first found where it is
    /// usually installed.
    public var resolvedCLIPath: String? {
        if let cliPath, !cliPath.trimmingCharacters(in: .whitespaces).isEmpty { return Self.expandingTilde(cliPath) }
        return (Self.cliSearchPaths.map(Self.expandingTilde) + Self.releaseCLIPaths())
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// cardano-cli in unpacked node releases, such as
    /// `~/cardano/cardano-node-11.1.2-macos-arm64/bin`, newest first.
    static func releaseCLIPaths() -> [String] {
        let folder = expandingTilde("~/cardano")
        let releases = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return releases.filter { $0.hasPrefix("cardano-node-") }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { "\(folder)/\($0)/bin/cardano-cli" }
    }
}
