import Foundation
import SwiftCardanoTokenRegistry
import SwiftCardanoTokenRegistryClient
import TxWorkshopCore

/// Looks token names up in the Cardano token registry (CIP-26).
public struct TokenRegistryLookup: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The registry for `network`, if it has one.
    static func endpoint(for network: CardanoNetwork) -> URL? {
        switch network {
        case .mainnet: Endpoint.mainnet
        // `Endpoint.preprod` (metadata.cardano-testnet.iohkdev.io) is retired;
        // the testnets share one metadata server.
        case .preprod, .preview: Endpoint.preview
        case .custom: nil
        }
    }

    /// What the registry knows about `assets`. Assets it does not know are
    /// left out.
    public func lookup(_ assets: [AssetDetail], network: CardanoNetwork) async throws -> [TokenInfo] {
        guard let endpoint = Self.endpoint(for: network) else { return [] }
        let subjects = Set(assets.map(\.registrySubject)).sorted().compactMap { try? Subject($0) }
        guard !subjects.isEmpty else { return [] }
        let entries = try await RegistryClient(baseURL: endpoint, session: session)
            .batchQuery(subjects: subjects, properties: ["name", "ticker", "decimals"])
        return entries.compactMap { entry in
            guard let subject = entry.subject?.value else { return nil }
            let info = TokenInfo(
                subject: subject, name: entry.name?.value.value,
                ticker: entry.ticker?.value.value, decimals: entry.decimals?.value.value
            )
            return info.name == nil && info.ticker == nil ? nil : info
        }
        .sorted { $0.subject < $1.subject }
    }
}
