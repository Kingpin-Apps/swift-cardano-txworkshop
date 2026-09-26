import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Transaction inspector")
struct TransactionInspectorTests {
    @Test("A preprod transaction decodes with its on-chain id")
    func inspectsPreprodTransaction() async throws {
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

    /// A transaction whose witness set carries one datum: `datumDepth` nested
    /// arrays around a 0. The tx array, witness map and datum list add three
    /// CBOR levels, so a depth of 124 puts the whole transaction at the
    /// decoder's 128-level cap.
    private func transaction(datumDepth: Int) -> Data {
        let body = Data([0xa3, 0x00, 0x81, 0x82, 0x58, 0x20]) + Data(count: 32)
            + Data([0x00, 0x01, 0x80, 0x02, 0x00])
        let datum = Data(repeating: 0x81, count: datumDepth) + Data([0x00])
        let witnessSet = Data([0xa1, 0x04, 0x81]) + datum
        return Data([0x84]) + body + witnessSet + Data([0xf5, 0xf6])
    }

    @Test("A datum nested to the depth cap decodes on a cooperative thread")
    func inspectsDeeplyNestedDatum() async throws {
        // Used to overflow the task's stack (SIGBUS) at ~100 levels.
        let bytes = transaction(datumDepth: 124)
        let summary = try await TransactionInspector().inspect(bytes)
        #expect(summary.byteCount == bytes.count)
        _ = try await TransactionInspector().inspection(of: bytes)
    }

    @Test("A datum nested past the depth cap is reported, not crashed on")
    func rejectsTooDeeplyNestedDatum() async {
        await #expect(throws: InspectionError.self) {
            _ = try await TransactionInspector().inspect(self.transaction(datumDepth: 200))
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
