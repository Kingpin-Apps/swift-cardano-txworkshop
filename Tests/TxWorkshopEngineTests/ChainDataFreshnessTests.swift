import BigInt
import Foundation
import OrderedCollections
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Keeping chain data until the epoch turns")
struct ChainDataFreshnessTests {
    /// Preview's system start; its epochs are one day long from there.
    let previewStart = Date(timeIntervalSince1970: 1_666_656_000)

    func snapshot(fetchedAt: Date, parameters: Bool = true) -> ChainContextSnapshot {
        ChainContextSnapshot(fetchedAt: fetchedAt, utxos: [], protocolParameters: parameters ? Data("{}".utf8) : nil, tipSlot: 1)
    }

    @Test("Preview epochs are a day long, mainnet's start at 208 on the Shelley fork")
    func epochs() {
        #expect(ChainDataFreshness.epoch(at: previewStart.addingTimeInterval(86_400 * 3 + 5), on: .preview) == 3)
        // Mainnet's Shelley fork: 2020-07-29T21:44:51Z.
        #expect(ChainDataFreshness.epoch(at: Date(timeIntervalSince1970: 1_596_059_091), on: .mainnet) == 208)
        #expect(ChainDataFreshness.epoch(at: .now, on: .custom(magic: 42)) == nil)
    }

    @Test("Fetched once, then again only when it is missing a part or the epoch turned")
    func needsFetch() {
        let fetched = previewStart.addingTimeInterval(86_400 * 10 + 100)
        #expect(ChainDataFreshness.needsFetch(nil, network: .preview))
        #expect(ChainDataFreshness.needsFetch(snapshot(fetchedAt: fetched, parameters: false), network: .preview, now: fetched))
        #expect(!ChainDataFreshness.needsFetch(snapshot(fetchedAt: fetched), network: .preview, now: fetched.addingTimeInterval(3_600)))
        #expect(ChainDataFreshness.needsFetch(snapshot(fetchedAt: fetched), network: .preview, now: fetched.addingTimeInterval(86_400)))
        // A network without a known timeline keeps what it has.
        #expect(!ChainDataFreshness.needsFetch(snapshot(fetchedAt: fetched), network: .custom(magic: 42), now: fetched.addingTimeInterval(864_000)))
    }

    @Test("A UTxO's tokens are listed with their names and quantities")
    func tokens() throws {
        let (_, utxo, _) = try TransactionComposerTests.setup()
        let policy = try ScriptHash(payload: Data(repeating: 0xAB, count: 28))
        let asset = Asset(OrderedDictionary(uniqueKeysWithValues: [
            (try AssetName(payload: Data("HOSKY".utf8)), BigInt(1_000)),
            (try AssetName(payload: Data([0x00, 0x01])), BigInt(2)),
        ]))
        let held = UTxO(
            input: utxo.input,
            output: TransactionOutput(address: utxo.output.address, amount: Value(coin: 2_000_000, multiAsset: MultiAsset([policy: asset])))
        )
        let tokens = TransactionComposer.tokens(utxoHex: try held.toCBORData().hex)
        #expect(tokens.count == 2)
        #expect(tokens.first { $0.name == "HOSKY" }?.quantity == "1000")
        #expect(tokens.first { $0.nameHex == "0001" }?.name == nil)
    }
}
