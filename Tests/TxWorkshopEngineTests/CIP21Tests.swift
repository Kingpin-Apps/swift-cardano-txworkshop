import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// CIP-21 in the app: what Build makes, and building a transaction again so
/// hardware wallets can sign it. The rules themselves are tested in
/// swift-cardano-cips.
@Suite("CIP-21")
struct CIP21Tests {
    @Test("A transaction the builder makes is already canonical")
    func built() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address, lovelace: 5_000_000)], changeAddress: address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let report = try CIP21Check.report(built.transaction)
        #expect(report.findings.filter { $0.rule.hasPrefix("canonical") }.isEmpty, "\(report.findings)")
        #expect(report.mode == .ordinary)
    }

    @Test("Certificates hardware wallets cannot sign are named, and building for them says so")
    func certificates() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let stake = try GovernanceBuildingTests.stakeAddress()
        let pool = String(repeating: "ab", count: 28)
        var recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address,
            certificates: [CertificateItem(certificate: .registerAndDelegateStake(stakeAddress: stake, pool: pool))]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let report = try CIP21Check.report(built.transaction)
        #expect(report.findings.contains { $0.rule == "prohibited-certificate" && !$0.fixable })

        recipe.cip21Compatible = true
        await #expect {
            _ = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        } throws: { error in
            String(describing: error).contains("CIP-21")
        }
    }

    @Test("A pool registration signs alone, without withdrawals, mint or script data")
    func poolRegistration() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let draft = try CertificateBuildingTests().poolDraft(isUpdate: false)
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address,
            certificates: [
                CertificateItem(certificate: .registerPool(draft)),
                CertificateItem(certificate: .registerStake(stakeAddress: try GovernanceBuildingTests.stakeAddress())),
            ]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let report = try CIP21Check.report(built.transaction)
        #expect(report.mode == .poolRegistration)
        #expect(report.findings.contains { $0.rule == "pool-registration" && $0.path == "certificates" })
    }

    @Test("The fixture's script spend signs in Plutus mode")
    func plutusMode() throws {
        let report = try CIP21Check.report(try TransactionInspectionTests.bytes("conway-tx"))
        #expect(report.mode == .plutus)
    }

    @Test("A recipe that needs a rewrite is rebuilt for hardware wallets, with the fee for its new bytes")
    func rebuildFromRecipe() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        // The pool's owners are written as a list while the inputs are a
        // tagged set: a mix hardware wallets refuse.
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], changeAddress: address,
            certificates: [CertificateItem(certificate: .registerPool(try CertificateBuildingTests().poolDraft(isUpdate: false)))]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        #expect(try CIP21Check.report(built.transaction).findings.map(\.rule) == ["set-tags"])

        let result = try await CIP21Rebuild.rebuild(built.transaction, recipe: recipe, snapshot: snapshot, network: .preprod)
        #expect(result.source == .recipe)
        #expect(result.report.isCompatible, "\(result.report.findings)")
        #expect(result.recipe?.cip21Compatible == true)
        // Three bytes of tag, at 44 lovelace a byte.
        #expect(result.fee == result.previousFee + 3 * 44)
        #expect(result.id != built.id)
        let old = try TransactionValidation.decode(built.transaction).transactionBody.inputs.asArray
        let new = try TransactionValidation.decode(result.transaction).transactionBody.inputs.asArray
        #expect(Set(new) == Set(old), "The same inputs.")
        // Built again from its kept form, it comes out the same.
        let again = try await TransactionComposer().compose(try #require(result.recipe), snapshot: snapshot, network: .preprod)
        #expect(try CIP21Check.report(again.transaction).isCompatible)
    }
}
