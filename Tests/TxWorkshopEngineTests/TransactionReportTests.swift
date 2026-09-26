import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Reports")
struct TransactionReportTests {
    static func report() async throws -> TransactionReport {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let inspection = try await TransactionInspector().inspection(of: bytes, network: .preprod)
        return TransactionReport(inspection: inspection, transaction: bytes, network: .preprod, notes: "Check | the fee\nsecond line")
    }

    @Test("Markdown has a heading per section and one table row per fact")
    func markdown() async throws {
        let report = try await Self.report()
        let markdown = report.markdown(generatedAt: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(markdown.hasPrefix("# Transaction \(report.inspection.summary.id)\n"))
        #expect(markdown.contains("Network: preprod"))
        #expect(markdown.contains("## Notes\n\nCheck | the fee\nsecond line"))
        for (section, facts) in report.sections {
            #expect(markdown.contains("## \(TransactionReport.heading(section))\n"))
            for fact in facts {
                #expect(markdown.contains("| \(TransactionReport.cell(fact.label)) | \(TransactionReport.cell(fact.value)) |"))
            }
        }
        #expect(markdown.contains("GeniusYield: Order placed"))
        #expect(TransactionReport.cell("a|b\nc") == "a\\|b c")
    }

    @Test("JSON carries the id, CBOR, validator view and facts")
    func json() async throws {
        let report = try await Self.report()
        let object = try #require(try JSONSerialization.jsonObject(with: report.json()) as? [String: Any])
        #expect(object["id"] as? String == report.inspection.summary.id)
        #expect(object["network"] as? String == "preprod")
        #expect(object["cborHex"] as? String == report.transaction.hex)
        #expect((object["signers"] as? [String])?.count == 1)
        #expect((object["transaction"] as? [String: Any])?["fee"] as? Int == Int(report.inspection.view.fee))
        #expect((object["facts"] as? [[String: Any]])?.count == report.inspection.facts.count)
    }
}
