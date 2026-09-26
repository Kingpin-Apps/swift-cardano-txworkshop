import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Comparing transactions")
struct TransactionDiffTests {
    static func inspection(_ bytes: Data) async throws -> TransactionInspection {
        try await TransactionInspector().inspection(of: bytes, network: .preprod)
    }

    @Test("A transaction compared with itself is identical")
    func identical() async throws {
        let order = try await Self.inspection(try TransactionInspectionTests.bytes("conway-tx"))
        let diff = TransactionDiff(from: order, to: order)
        #expect(diff.relation == .identical)
        #expect(diff.changes.isEmpty)
    }

    @Test("An unsigned copy has the same body; only the signatures differ")
    func unsignedVersusSigned() async throws {
        let signedBytes = try TransactionInspectionTests.bytes("conway-tx")
        var unsigned = try Transaction.fromCBOR(data: signedBytes)
        unsigned.transactionWitnessSet.vkeyWitnesses = nil
        let signed = try await Self.inspection(signedBytes)
        let bare = try await Self.inspection(try unsigned.toCBORData())

        #expect(signed.signers.count == 1)
        #expect(signed.signers.allSatisfy { $0.count == 56 })
        #expect(bare.signers.isEmpty)

        let diff = TransactionDiff(from: bare, to: signed)
        #expect(diff.relation == .sameBody)
        let sections = Set(diff.changes.map(\.section))
        #expect(sections.isSubset(of: [.transaction, .witnesses]))
        #expect(diff.changes.contains { $0.key == "count" && $0.old == "0" && $0.new == "1" })
        // The new signature shows up as the required signer being met, or as a new signer.
        #expect(diff.changes.contains { $0.section == .witnesses && $0.new == "signed" })
        #expect(!diff.changes.contains { $0.key == "id" })
    }

    @Test("Different transactions list what was added, removed and changed")
    func different() async throws {
        let order = try await Self.inspection(try TransactionInspectionTests.bytes("conway-tx"))
        let plutus = try await Self.inspection(try TransactionInspectionTests.bytes("alonzo-plutus-v1"))
        let diff = TransactionDiff(from: order, to: plutus)
        #expect(diff.relation == .different)
        #expect(diff.changes.contains { $0.key == "id" })
        #expect(diff.changes.contains { $0.key == "fee" && $0.old != nil && $0.new != nil })
        #expect(diff.changes.contains { $0.section == .inputs && $0.new == nil })
        #expect(diff.changes.contains { $0.section == .inputs && $0.old == nil })
        // Sections come in order.
        let positions = diff.changes.map { TransactionFact.Section.allCases.firstIndex(of: $0.section)! }
        #expect(positions == positions.sorted())
    }

    @Test("Facts have unique ids")
    func uniqueFacts() async throws {
        for name in ["conway-tx", "alonzo-plutus-v1"] {
            let facts = try await Self.inspection(try TransactionInspectionTests.bytes(name)).facts
            #expect(Set(facts.map(\.id)).count == facts.count, "\(name)")
            #expect(facts.contains { $0.section == .metadata } == (name == "conway-tx"))
        }
    }
}
