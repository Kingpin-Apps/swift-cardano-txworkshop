import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Fetching by hash")
struct TransactionFetcherTests {
    static let hash = "f5cd70603aedb09e99c454f56f7afa59ad67c1def54d9022b70b8550a7b60700"

    static func source(_ network: CardanoNetwork, kind: ProviderKind = .koios) -> TransactionFetcher.Source {
        .init(provider: ProviderConfiguration(name: network.id, kind: kind, network: network), apiKey: nil)
    }

    /// Serves the fixture on preprod only.
    static func fetcher() throws -> TransactionFetcher {
        let url = try #require(Bundle.module.url(forResource: "conway-tx", withExtension: "hex", subdirectory: "Fixtures"))
        let bytes = try TxDocumentCodec.bytes(fromHex: try String(contentsOf: url, encoding: .utf8))
        return TransactionFetcher { provider, _ in
            StubContext(network: provider.network, cbor: provider.network == .preprod ? bytes : nil)
        }
    }

    @Test("The network that has the transaction wins")
    func findsTheNetwork() async throws {
        let fetched = try await Self.fetcher().fetch(hash: Self.hash, from: [Self.source(.mainnet), Self.source(.preprod), Self.source(.preview)])
        #expect(fetched.network == .preprod)
        #expect(try await TransactionInspector().inspect(fetched.cbor).id == Self.hash)
    }

    @Test("A miss everywhere says why for each network")
    func notFound() async throws {
        await #expect(throws: FetchError.self) {
            _ = try await Self.fetcher().fetch(hash: Self.hash, from: [Self.source(.mainnet), Self.source(.preview)])
        }
    }

    @Test("Bad ids and missing providers are reported")
    func badInput() async throws {
        await #expect(throws: FetchError.notAHash) {
            _ = try await Self.fetcher().fetch(hash: "abc", from: [Self.source(.preprod)])
        }
        await #expect(throws: FetchError.noProviders) {
            _ = try await Self.fetcher().fetch(hash: Self.hash, from: [Self.source(.preprod, kind: .ogmios)])
        }
    }
}

/// A chain context that knows one transaction, or none.
private struct StubContext: ChainContext {
    let network: CardanoNetwork
    let cbor: Data?

    var name: String { "stub" }
    var type: ContextType { .online }
    var networkId: NetworkId { network == .mainnet ? .mainnet : .testnet }

    func transactionCBOR(hash: TransactionId) async throws -> Data {
        guard let cbor else { throw CardanoChainError.valueError("not found") }
        return cbor
    }

    func protocolParameters() async throws -> ProtocolParameters { throw CardanoChainError.notImplemented(nil) }
    func genesisParameters() async throws -> GenesisParameters { throw CardanoChainError.notImplemented(nil) }
    func epoch() async throws -> Int { 0 }
    func era() async throws -> Era? { nil }
    func lastBlockSlot() async throws -> Int { 0 }
}
