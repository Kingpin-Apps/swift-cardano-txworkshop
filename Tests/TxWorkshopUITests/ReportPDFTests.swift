import CoreGraphics
import Foundation
import Testing
import TxWorkshopCore
import TxWorkshopEngine

@testable import TxWorkshopUI

@Suite("PDF report")
@MainActor
struct ReportPDFTests {
    @Test("Every row lands on a Letter page, and the PDF opens")
    func pages() async throws {
        let url = try #require(Bundle.module.url(forResource: "conway-tx", withExtension: "hex", subdirectory: "Fixtures"))
        let bytes = try TxDocumentCodec.bytes(fromHex: try String(contentsOf: url, encoding: .utf8))
        let inspection = try await TransactionInspector().inspection(of: bytes, network: .preprod)
        let report = TransactionReport(inspection: inspection, transaction: bytes, network: .preprod, notes: "One\nTwo")

        let rows = ReportPDF.rows(for: report)
        #expect(rows.first == .heading("Notes"))
        #expect(rows.count == 3 + report.sections.count + report.sections.map(\.facts.count).reduce(0, +))

        let data = ReportPDF.render(report)
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        let pages = ReportPDF.pages(rows)
        #expect(pages.flatMap(\.self) == rows)
        #expect(pages.allSatisfy { $0.map(ReportPDF.height).reduce(0, +) <= ReportPDF.bodyHeight })
        #expect(document.numberOfPages == pages.count)
        let box = try #require(document.page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == ReportPDF.pageSize)
        try data.write(to: FileManager.default.temporaryDirectory.appending(path: "txworkshop-report.pdf"))
    }
}
