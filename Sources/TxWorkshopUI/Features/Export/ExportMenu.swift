import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import UniformTypeIdentifiers

/// Exports the transaction as JSON, Markdown or a PDF report.
struct ExportMenu: View {
    let document: TxWorkshopDocument
    let inspection: TransactionInspection
    @State private var file = ReportFile()
    @State private var isExporting = false
    @State private var problem: String?

    var body: some View {
        Menu {
            Button {
                export(.json)
            } label: {
                Text("JSON", bundle: #bundle)
            }
            Button {
                export(.markdown)
            } label: {
                Text("Markdown", bundle: #bundle)
            }
            Button {
                export(.pdf)
            } label: {
                Text("PDF Report", bundle: #bundle)
            }
        } label: {
            Label {
                Text("Export", bundle: #bundle)
            } icon: {
                Image(systemName: "doc.badge.arrow.up")
            }
        }
        .fileExporter(
            isPresented: $isExporting, document: file, contentType: file.contentType,
            defaultFilename: "Transaction \(inspection.summary.id.prefix(8))"
        ) { result in
            if case .failure(let error) = result { problem = String(describing: error) }
        }
        .alert(String(localized: "Export failed", bundle: #bundle), item: $problem) { _ in
            Button(role: .cancel) {} label: { Text("OK", bundle: #bundle) }
        } message: { problem in
            Text(verbatim: problem)
        }
    }

    private func export(_ type: UTType) {
        guard let transaction = document.content.transaction else { return }
        let report = TransactionReport(
            inspection: inspection, transaction: transaction,
            network: document.content.network, notes: document.content.notes
        )
        do {
            file.data = switch type {
            case .json: try report.json()
            case .pdf: ReportPDF.render(report)
            default: Data(report.markdown().utf8)
            }
            file.contentType = type
            isExporting = true
        } catch {
            problem = String(describing: error)
        }
    }
}
