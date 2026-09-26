import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Transaction inspector")
struct TransactionInspectorTests {
    @Test("A mainnet transaction decodes with its on-chain id")
    func inspectsMainnetTransaction() async throws {
        let url = try #require(Bundle.module.url(forResource: "conway-tx", withExtension: "hex", subdirectory: "Fixtures"))
        let bytes = try TxDocumentCodec.bytes(fromHex: try String(contentsOf: url, encoding: .utf8))
        let summary = try await TransactionInspector().inspect(bytes)
        #expect(summary.id == "f5cd70603aedb09e99c454f56f7afa59ad67c1def54d9022b70b8550a7b60700")
        #expect(summary.byteCount == bytes.count)
        #expect(summary.possibleEras == "conway")
        #expect(summary.isSigned)
    }

    @Test("Bytes that are not a transaction are reported, not trapped on")
    func rejectsGarbage() async {
        await #expect(throws: InspectionError.self) {
            _ = try await TransactionInspector().inspect(Data([0x01, 0x02, 0x03]))
        }
    }

    @Test("Every provider maps to a chain context or says why not")
    func offlineAndDirectProviders() async {
        await #expect(throws: ChainContextFactoryError.offline) {
            _ = try await ChainContextFactory().makeContext(
                for: ProviderConfiguration(name: "Off", kind: .offline, network: .mainnet), apiKey: nil)
        }
        await #expect(throws: ChainContextFactoryError.needsDirectDistribution) {
            _ = try await ChainContextFactory().makeContext(
                for: ProviderConfiguration(name: "Node", kind: .localNode, network: .mainnet), apiKey: nil)
        }
    }
}
