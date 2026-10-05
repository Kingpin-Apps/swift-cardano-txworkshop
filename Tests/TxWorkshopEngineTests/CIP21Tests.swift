import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// CIP-21: what hardware wallets ask of a transaction, and rewriting one to
/// fit.
@Suite("CIP-21")
struct CIP21Tests {
    /// Hand-written CBOR, so each rule can be broken on purpose.
    struct Writer {
        var data = Data()
        mutating func head(_ major: UInt8, _ value: UInt64) { RawCBOR.head(major, value, into: &data) }
        mutating func raw(_ bytes: [UInt8]) { data += bytes }
        mutating func bytes(_ bytes: Data) {
            head(2, UInt64(bytes.count))
            data += bytes
        }
    }

    static func address() throws -> Data {
        let (_, _, address) = try TransactionComposerTests.setup()
        return try Address(from: .string(address)).toBytes()
    }

    /// A transaction that breaks the encoding rules: keys out of order, an
    /// indefinite input list, an overlong fee, an empty certificate list, and
    /// one signature.
    static func messy() throws -> Data {
        var w = Writer()
        w.head(4, 4)
        w.head(5, 4)
        // outputs first: out of canonical order.
        w.head(0, 1)
        w.head(4, 1)
        w.head(4, 2); w.bytes(try address()); w.head(0, 2_000_000)
        // inputs, indefinite.
        w.head(0, 0)
        w.raw([0x9f])
        w.head(4, 2); w.bytes(Data(repeating: 0xAB, count: 32)); w.head(0, 0)
        w.raw([0xff])
        // fee, written in two bytes it does not need.
        w.head(0, 2)
        w.raw([0x19, 0x00, 0x10])
        // an empty certificate list.
        w.head(0, 4)
        w.head(4, 0)
        // witnesses: one signature.
        w.head(5, 1)
        w.head(0, 0)
        w.head(4, 1)
        w.head(4, 2); w.bytes(Data(repeating: 0x01, count: 32)); w.bytes(Data(repeating: 0x02, count: 64))
        w.raw([0xf5, 0xf6])
        return w.data
    }

    @Test("Each encoding rule a transaction breaks is named")
    func findings() throws {
        let report = try CIP21Check.report(try Self.messy())
        let rules = Set(report.findings.map(\.rule))
        #expect(rules == ["canonical-sorting", "canonical-definite", "canonical-length", "empty-collection"])
        #expect(report.findings.allSatisfy { $0.fixable })
        #expect(report.mode == .ordinary)
        #expect(report.findings.first { $0.rule == "canonical-definite" }?.path == "inputs")
        #expect(report.findings.first(where: { $0.rule == "canonical-length" })?.path == "fee")
    }

    @Test("The rewrite is canonical, means the same, and drops the old signature")
    func transform() throws {
        let messy = try Self.messy()
        let result = try CIP21Transform.compatible(messy)
        #expect(result.changed)
        #expect(result.droppedSignatures == 1)
        #expect(result.remaining.isEmpty, "\(result.remaining)")
        #expect(try CIP21Check.report(result.bytes).isCompatible)

        let before = try Transaction.fromCBOR(data: messy).transactionBody
        let after = try Transaction.fromCBOR(data: result.bytes).transactionBody
        #expect(after.fee == before.fee)
        #expect(after.inputs.asArray.map(\.transactionId) == before.inputs.asArray.map(\.transactionId))
        #expect(after.outputs.count == before.outputs.count)
        #expect(after.certificates == nil)
        // Rewriting again changes nothing.
        let again = try CIP21Transform.compatible(result.bytes)
        #expect(!again.changed && again.bytes == result.bytes)
    }

    @Test("A transaction the builder makes is already compatible")
    func built() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address, lovelace: 5_000_000)], changeAddress: address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let report = try CIP21Check.report(built.transaction)
        #expect(report.findings.filter { $0.rule.hasPrefix("canonical") }.isEmpty, "\(report.findings)")
        #expect(report.mode == .ordinary)
    }

    @Test("Certificates hardware wallets cannot sign are named, and stay after a rewrite")
    func certificates() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let stake = try GovernanceBuildingTests.stakeAddress()
        let pool = String(repeating: "ab", count: 28)
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address,
            certificates: [CertificateItem(certificate: .registerAndDelegateStake(stakeAddress: stake, pool: pool))]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let report = try CIP21Check.report(built.transaction)
        #expect(report.findings.contains { $0.rule == "prohibited-certificate" && !$0.fixable })
        let result = try CIP21Transform.compatible(built.transaction)
        #expect(result.remaining.contains { $0.rule == "prohibited-certificate" })
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
}
