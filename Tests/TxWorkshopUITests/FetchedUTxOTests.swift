import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore
import TxWorkshopEngine

@testable import TxWorkshopUI

/// Fetching an address's UTxOs replaces those listed, so a spent one is not
/// built with.
@Suite("Fetched UTxOs")
@MainActor
struct FetchedUTxOTests {
    /// A UTxO at a fresh address, as CBOR hex, and its `txid#index`.
    static func utxo(_ byte: UInt8, index: UInt16 = 0) throws -> (hex: String, id: String) {
        let key: PaymentVerificationKey = try PaymentSigningKey.generate().toVerificationKey()
        let address = try Address(paymentPart: .verificationKeyHash(try key.hash()), network: .testnet)
        let input = TransactionInput(transactionId: TransactionId(payload: Data(repeating: byte, count: 32)), index: index)
        let utxo = UTxO(input: input, output: TransactionOutput(address: address, amount: Value(coin: 2_000_000)))
        let hex = TxDocumentCodec.hex(try utxo.toCBORData())
        return (hex, try #require(TransactionComposer.describe(utxoHex: hex)?.id))
    }

    @Test("The fetched UTxOs replace those listed")
    func replaces() throws {
        let (spent, kept, new) = (try Self.utxo(1), try Self.utxo(2), try Self.utxo(3))
        var recipe = BuildRecipe(utxos: [spent.hex, kept.hex])
        SourcesSection.replaceUTxOs(in: &recipe, with: [kept.hex, new.hex])
        #expect(recipe.utxos == [kept.hex, new.hex])
    }

    @Test("Choices for UTxOs that are gone go with them; others stay")
    func choices() throws {
        let (spent, kept) = (try Self.utxo(1), try Self.utxo(2))
        let elsewhere = String(repeating: "ab", count: 32) + "#0"
        var recipe = BuildRecipe(utxos: [spent.hex, kept.hex])
        recipe.setChoice(.always, for: spent.id)
        recipe.setChoice(.never, for: kept.id)
        recipe.setChoice(.always, for: elsewhere)
        SourcesSection.replaceUTxOs(in: &recipe, with: [kept.hex])
        #expect(recipe.choice(for: spent.id) == .automatic)
        #expect(recipe.choice(for: kept.id) == .never)
        #expect(recipe.choice(for: elsewhere) == .always)
    }
}
