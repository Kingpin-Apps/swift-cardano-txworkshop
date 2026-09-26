import Foundation
import OrderedCollections
import SwiftCardanoChain
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Looking inputs and names up", .serialized)
struct LookupTests {
    static let provider = ProviderConfiguration(name: "preprod", kind: .koios, network: .preprod)

    static func transaction() throws -> (bytes: Data, transaction: Transaction) {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        return (bytes, try Transaction.fromCBOR(data: bytes))
    }

    @Test("Found inputs are saved with their spent status; the rest are reported missing")
    func resolvesInputs() async throws {
        let (bytes, transaction) = try Self.transaction()
        let inputs = transaction.transactionBody.inputs.asArray
        let known = UTxO(input: inputs[0], output: transaction.transactionBody.outputs[0])
        let resolver = InputResolver { _, _ in UTxOContext(known: [InputResolver.id(inputs[0]): (known, true)]) }

        let resolved = try await resolver.resolve(transaction: bytes, provider: Self.provider, apiKey: nil)
        #expect(resolved.utxos.count == 1)
        #expect(resolved.spent == [InputResolver.id(inputs[0])])
        #expect(resolved.missing.contains(InputResolver.id(inputs[1])))

        let snapshot = ChainContextSnapshot(fetchedAt: .now, utxos: resolved.utxos, spentInputs: resolved.spent)
        let inspection = try await TransactionInspector().inspection(of: bytes, network: .preprod, chainContext: snapshot)
        let first = try #require(inspection.inputs.first { $0.id == InputResolver.id(inputs[0]) })
        #expect(first.status == .spent)
        #expect(first.output?.lovelace == inspection.outputs[0].lovelace)
        #expect(first.output?.index == Int(inputs[0].index))
        #expect(inspection.inputs.first { $0.id == InputResolver.id(inputs[1]) }?.status == .notFound)

        let unresolved = try await TransactionInspector().inspection(of: bytes, network: .preprod)
        #expect(unresolved.inputs.allSatisfy { $0.status == .unresolved && $0.output == nil })
    }

    @Test("A provider that fails for every input is an error")
    func resolveFails() async throws {
        let (bytes, _) = try Self.transaction()
        let resolver = InputResolver { _, _ in UTxOContext(known: [:], fails: true) }
        await #expect(throws: ResolveError.self) {
            _ = try await resolver.resolve(transaction: bytes, provider: Self.provider, apiKey: nil)
        }
    }

    @Test("Registry names reach the assets they belong to")
    func registryNames() async throws {
        let (bytes, _) = try Self.transaction()
        let mint = try await TransactionInspector().inspection(of: bytes, network: .preprod).mint
        let asset = try #require(mint.first)
        RegistryURLProtocol.body = Data(#"""
            {"subjects": [{"subject": "\#(asset.registrySubject)",
              "name": {"value": "Order NFT", "sequenceNumber": 0, "signatures": []},
              "ticker": {"value": "GYO", "sequenceNumber": 0, "signatures": []},
              "decimals": {"value": 0, "sequenceNumber": 0, "signatures": []}}]}
            """#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryURLProtocol.self]
        let lookup = TokenRegistryLookup(session: URLSession(configuration: configuration))

        let tokens = try await lookup.lookup(mint, network: .preprod)
        #expect(tokens == [TokenInfo(subject: asset.registrySubject, name: "Order NFT", ticker: "GYO", decimals: 0)])
        #expect(RegistryURLProtocol.lastURL?.absoluteString == "https://metadata.cardano-testnet.iohkdev.io/metadata/query")
        #expect(try await lookup.lookup(mint, network: .custom(magic: 42)).isEmpty)

        let snapshot = ChainContextSnapshot(fetchedAt: .now, utxos: [], tokens: tokens)
        let named = try await TransactionInspector().inspection(of: bytes, network: .preprod, chainContext: snapshot)
        let namedAsset = try #require(named.mint.first { $0.id == asset.id })
        #expect(namedAsset.displayName == "Order NFT")
        #expect(namedAsset.nameSource == .registry)
        #expect(namedAsset.ticker == "GYO")
    }

    @Test("CIP-25 names are read from version 1 text keys and version 2 byte keys")
    func cip25() throws {
        let policy = String(repeating: "ab", count: 28)
        let policyBytes = try TxDocumentCodec.bytes(fromHex: policy)
        let v1: TransactionMetadatum = .map([
            .text(policy): .map([.text("Nami"): .map([.text("name"): .text("Nami #1")])]),
        ])
        #expect(AssetNames.cip25Names(v1) == [policy + Data("Nami".utf8).hex: "Nami #1"])

        let v2: TransactionMetadatum = .map([
            .bytes(policyBytes): .map([.bytes(Data([0x01, 0x02])): .map([.text("name"): .list([.text("Long "), .text("name")])])]),
            .text("version"): .int(2),
        ])
        #expect(AssetNames.cip25Names(v2) == [policy + "0102": "Long name"])

        let names = AssetNames(metadata: [721: v1], registry: [TokenInfo(subject: policy + Data("Nami".utf8).hex, name: "Registry name")])
        #expect(names[policy + Data("Nami".utf8).hex]?.source == .cip25)
    }
}

/// Answers the registry's batch query with one canned body.
final class RegistryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastURL: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastURL = request.url
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A chain context that knows some outputs.
private struct UTxOContext: ChainContext {
    let known: [String: (UTxO, Bool)]
    var fails = false

    var name: String { "stub" }
    var type: ContextType { .online }
    var networkId: NetworkId { .testnet }

    func utxo(input: TransactionInput) async throws -> (UTxO, isSpent: Bool)? {
        if fails { throw CardanoChainError.valueError("offline") }
        return known[InputResolver.id(input)].map { ($0.0, isSpent: $0.1) }
    }

    func protocolParameters() async throws -> ProtocolParameters { throw CardanoChainError.notImplemented(nil) }
    func genesisParameters() async throws -> GenesisParameters { throw CardanoChainError.notImplemented(nil) }
    func epoch() async throws -> Int { 0 }
    func era() async throws -> Era? { nil }
    func lastBlockSlot() async throws -> Int { 0 }
}
