import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Chain summary")
struct ChainSummaryTests {
    @Test("A snapshot reads as its tip, version, key parameters and cost models")
    func summary() throws {
        let snapshot = try TransactionValidationTests.snapshot()
        let summary = ChainSummary(snapshot)
        #expect(summary.tipSlot == snapshot.tipSlot)
        #expect(summary.protocolVersion != nil)
        #expect(summary.parameters.map(\.name).contains("Fee per byte"))
        #expect(summary.parameters.contains { $0.name == "Pool deposit" && $0.value.hasPrefix("₳") })
        #expect(!summary.costModels.isEmpty)
        #expect(summary.parametersJSON.contains("txFeePerByte"))
        #expect(summary.utxoCount == snapshot.utxos.count)
    }

    @Test("A snapshot with no parameters still reads")
    func empty() {
        let summary = ChainSummary(ChainContextSnapshot(fetchedAt: .now, utxos: []))
        #expect(summary.parameters.isEmpty && summary.protocolVersion == nil && summary.parametersJSON.isEmpty)
    }
}
