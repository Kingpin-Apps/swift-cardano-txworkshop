import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Transaction inspection")
struct TransactionInspectionTests {
    static func bytes(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "hex", subdirectory: "Fixtures"))
        return try TxDocumentCodec.bytes(fromHex: try String(contentsOf: url, encoding: .utf8))
    }

    @Test("CIP-14 fingerprints match the CIP's test vectors")
    func fingerprints() throws {
        let vectors: [(policy: String, name: String, fingerprint: String)] = [
            ("7eae28af2208be856f7a119668ae52a49b73725e326dc16579dcc373", "", "asset1rjklcrnsdzqp65wjgrg55sy9723kw09mlgvlc3"),
            ("7eae28af2208be856f7a119668ae52a49b73725e326dc16579dcc373", "504154415445", "asset13n25uv0yaf5kus35fm2k86cqy60z58d9xmde92"),
            ("1e349c9bdea19fd6c147626a5260bc44b71635f398b67c59881df209", "7eae28af2208be856f7a119668ae52a49b73725e326dc16579dcc373", "asset1aqrdypg669jgazruv5ah07nuyqe0wxjhe2el6f"),
        ]
        for vector in vectors {
            let policy = try TxDocumentCodec.bytes(fromHex: vector.policy)
            let name = vector.name.isEmpty ? Data() : try TxDocumentCodec.bytes(fromHex: vector.name)
            #expect(AssetFingerprint.fingerprint(policyID: policy, assetName: name) == vector.fingerprint)
        }
    }

    @Test("A Genius Yield order on preprod: script output, assets, message, redeemers")
    func geniusYieldOrder() async throws {
        let inspection = try await TransactionInspector().inspection(of: try Self.bytes("conway-tx"), network: .preprod)
        #expect(inspection.inputs.count == 2)
        #expect(inspection.outputs.count == 2)

        let order = inspection.outputs[0]
        #expect(order.address.paysToScript)
        #expect(order.address.kind == .enterprise)
        #expect(!order.address.isMainnet)
        #expect(!order.assets.isEmpty)
        #expect(order.assets.allSatisfy { $0.fingerprint?.hasPrefix("asset1") == true })
        // A legacy output: the datum is referenced by hash and supplied in the witnesses.
        guard case .hash(let hash)? = order.datum else {
            Issue.record("the order output should reference its datum by hash")
            return
        }
        let witnessed = try #require(inspection.datums.first { $0.hash == hash }, "no witness datum hashes to \(hash)")
        #expect(witnessed.tree.children?.isEmpty == false)

        #expect(inspection.metadata.map(\.label) == [674])
        #expect(inspection.metadata.first?.registeredAs == "Message (CIP-20)")
        #expect(inspection.metadata.first?.message == "GeniusYield: Order placed")

        #expect(!inspection.mint.isEmpty)
        #expect(inspection.redeemers.count == inspection.view.redeemerCount)
        #expect(inspection.redeemers.allSatisfy { $0.view.purpose != nil })
    }

    @Test("A Plutus V1 script prints as UPLC")
    func plutusListing() async throws {
        let inspection = try await TransactionInspector().inspection(of: try Self.bytes("alonzo-plutus-v1"), network: .mainnet)
        let script = try #require(inspection.scripts.first { $0.language == "plutusV1" })
        #expect(script.hash.count == 56)
        #expect(script.listing?.hasPrefix("(program") == true)
        #expect(!inspection.datums.isEmpty)
    }

    @Test("A validity window is placed in time on a known network")
    func validityTimes() async throws {
        let bytes = try Self.bytes("alonzo-plutus-v1")
        let mainnet = try await TransactionInspector().inspection(of: bytes, network: .mainnet).validity
        #expect(mainnet.startSlot != nil || mainnet.endSlot != nil)
        if mainnet.startSlot != nil { #expect(mainnet.start != nil) }
        let unknown = try await TransactionInspector().inspection(of: bytes, network: .custom(magic: 42)).validity
        #expect(unknown.start == nil && unknown.end == nil)
    }

    @Test("CIP-67 labels are read from asset names")
    func cip67() {
        #expect(AssetDetail.cip67Label(ofNameHex: "000de140" + "4e4654") == 222)
        #expect(AssetDetail.cip67Label(ofNameHex: "000643b0" + "4e4654") == 100)
        #expect(AssetDetail.cip67Label(ofNameHex: "4e4654") == nil)
    }
}
