import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import UniformTypeIdentifiers

/// Shares the transaction, copies its CBOR, or saves it as a cardano-cli
/// text envelope, raw CBOR or CBOR hex, or a report of it as JSON, Markdown
/// or PDF. The reports need the transaction
/// inspected; the envelope does not.
struct ExportShareMenu: View {
    let document: TxWorkshopDocument
    let transaction: Data
    let inspection: TransactionInspection?
    @State private var file = ReportFile()
    @State private var isExporting = false
    @State private var problem: String?

    var body: some View {
        Menu {
            if let envelope {
                ShareLink(item: envelope, preview: SharePreview(Text(verbatim: fileName))) {
                    Label {
                        Text("Share Transaction…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            Button {
                Clipboard.copy(TxDocumentCodec.hex(transaction))
            } label: {
                Label {
                    Text("Copy CBOR Hex", bundle: #bundle)
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }
            Section {
                Button {
                    save(envelope?.data, as: .cardanoTextEnvelope)
                } label: {
                    Label {
                        Text("Text Envelope (.tx)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.badge.gearshape")
                    }
                }
                .disabled(envelope == nil)
                Button {
                    save(transaction, as: .cardanoTransactionCBOR)
                } label: {
                    Label {
                        Text("CBOR (.cbor)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.zipper")
                    }
                }
                Button {
                    save(Data((TxDocumentCodec.hex(transaction) + "\n").utf8), as: .cardanoTransactionHex)
                } label: {
                    Label {
                        Text("CBOR Hex (.hex)", bundle: #bundle)
                    } icon: {
                        Image(systemName: "number")
                    }
                }
                Button {
                    exportReport(.json)
                } label: {
                    Label {
                        Text("JSON Report", bundle: #bundle)
                    } icon: {
                        Image(systemName: "curlybraces")
                    }
                }
                .disabled(inspection == nil)
                Button {
                    exportReport(.markdown)
                } label: {
                    Label {
                        Text("Markdown Report", bundle: #bundle)
                    } icon: {
                        Image(systemName: "text.document")
                    }
                }
                .disabled(inspection == nil)
                Button {
                    exportReport(.pdf)
                } label: {
                    Label {
                        Text("PDF Report", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.richtext")
                    }
                }
                .disabled(inspection == nil)
            } header: {
                Text("Export", bundle: #bundle)
            }
        } label: {
            Label {
                Text("Export & Share", bundle: #bundle)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .help(Text("Share the transaction, copy its CBOR, or export it as a text envelope, CBOR or a report", bundle: #bundle))
        .accessibilityIdentifier("exportShare")
        .fileExporter(isPresented: $isExporting, document: file, contentType: file.contentType, defaultFilename: fileName) { result in
            if case .failure(let error) = result { problem = String(describing: error) }
        }
        .alert(String(localized: "Export failed", bundle: #bundle), item: $problem) { _ in
            Button(role: .cancel) {} label: { Text("OK", bundle: #bundle) }
        } message: { problem in
            Text(verbatim: problem)
        }
    }

    /// The transaction as a text envelope file, written by swift-cardano-core.
    private var envelope: TextEnvelopeFile? {
        let content = TxDocumentContent(transaction: transaction, envelope: document.content.envelope)
        guard let data = try? TxDocumentCodec.file(for: content, format: .textEnvelope) else { return nil }
        return TextEnvelopeFile(data: data, name: fileName)
    }

    private var fileName: String {
        guard let id = inspection?.summary.id, !id.isEmpty else { return String(localized: "Transaction", bundle: #bundle) }
        return String(localized: "Transaction \(String(id.prefix(8)))", bundle: #bundle)
    }

    private func save(_ data: Data?, as type: UTType) {
        guard let data else { return }
        file.data = data
        file.contentType = type
        isExporting = true
    }

    private func exportReport(_ type: UTType) {
        guard let inspection else { return }
        let report = TransactionReport(
            inspection: inspection, transaction: transaction,
            network: document.content.network, notes: document.content.notes
        )
        do {
            let data: Data = switch type {
            case .json: try report.json()
            case .pdf: ReportPDF.render(report)
            default: Data(report.markdown().utf8)
            }
            save(data, as: type)
        } catch {
            problem = String(describing: error)
        }
    }
}

/// A transaction as a `.tx` file, to share.
struct TextEnvelopeFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .cardanoTextEnvelope) { $0.data }
            .suggestedFileName { $0.name + ".tx" }
    }
}
