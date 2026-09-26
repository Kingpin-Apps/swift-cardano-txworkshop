import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Building")
struct TransactionComposerTests {
    /// The fixture's chain data, and a key-address UTxO from it to spend.
    static func setup() throws -> (snapshot: ChainContextSnapshot, utxo: UTxO, address: String) {
        let snapshot = try TransactionValidationTests.snapshot()
        let utxos = TransactionValidation.utxos(snapshot)
        let utxo = try #require(utxos.first { $0.output.address.paymentPart.map { if case .verificationKeyHash = $0 { true } else { false } } ?? false && $0.output.amount.coin > 100_000_000 })
        return (snapshot, utxo, try utxo.output.address.toBech32())
    }

    @Test("A payment balances: inputs = outputs + fee, with change back")
    func payment() async throws {
        let (snapshot, utxo, address) = try Self.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex],
            outputs: [OutputDraft(address: address, lovelace: 10_000_000)],
            changeAddress: address,
            message: "Built by Tx Workshop"
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        #expect(built.inputs == [InputResolver.id(utxo.input)])
        #expect(built.fee.total > 150_000)
        #expect(built.totalIn == built.totalOut + Int64(built.fee.total))
        #expect(built.change != nil)

        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        #expect(inspection.summary.id == built.id)
        #expect(inspection.outputs.first?.lovelace == 10_000_000)
        #expect(inspection.metadata.first?.message == "Built by Tx Workshop")
        #expect(inspection.view.fee == built.fee.total)

        // Phase 1 finds nothing but the missing signature.
        let outcome = try await TransactionValidation().validate(built.transaction, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(outcome.errors.map(\.kind) == ["missingVKeyWitness"], "\(outcome.errors.map(\.message))")
    }

    @Test("An output without an amount gets the least the ledger allows")
    func minimumAda() async throws {
        let (snapshot, utxo, address) = try Self.setup()
        let recipe = BuildRecipe(utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        let first = try #require(inspection.outputs.first)
        #expect(first.lovelace > 800_000 && first.lovelace < 1_500_000)
    }

    @Test("Mistakes are named")
    func mistakes() async throws {
        let (snapshot, utxo, address) = try Self.setup()
        let hex = try utxo.toCBORData().hex
        await #expect(throws: ComposeError.badAddress("nope")) {
            _ = try await TransactionComposer().compose(BuildRecipe(utxos: [hex], outputs: [OutputDraft(address: "nope")], changeAddress: address), snapshot: snapshot, network: .preprod)
        }
        do {
            _ = try await TransactionComposer().compose(BuildRecipe(utxos: [hex], outputs: [OutputDraft(address: address, lovelace: 1)], changeAddress: address), snapshot: snapshot, network: .preprod)
            Issue.record("one lovelace should be below the minimum")
        } catch ComposeError.belowMinimum(let to, let minimum) {
            #expect(to == address)
            #expect(minimum > 800_000)
        }
        await #expect(throws: ComposeError.noProtocolParameters) {
            _ = try await TransactionComposer().compose(BuildRecipe(utxos: [hex], outputs: [], changeAddress: address), snapshot: nil, network: .preprod)
        }
    }

    @Test("A long message is split into 64-byte lines")
    func messageLines() throws {
        let data = try #require(try TransactionComposer.message(String(repeating: "é", count: 40)))
        guard case .metadata(let metadata) = data.data, case .map(let map)? = metadata[674], case .list(let lines)? = map[.text("msg")] else {
            Issue.record("expected a CIP-20 message")
            return
        }
        #expect(lines.count == 2)
        #expect(try TransactionComposer.message("  \n") == nil)
    }
}
