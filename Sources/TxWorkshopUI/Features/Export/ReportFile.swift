import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A finished report, handed to `fileExporter` to save.
@MainActor
@Observable
final class ReportFile: WritableDocument {
    nonisolated static let writableContentTypes: [UTType] = [.cardanoTextEnvelope, .cardanoTransactionCBOR, .cardanoTransactionHex, .json, .markdown, .pdf]

    var data: Data
    var contentType: UTType

    init(data: Data = Data(), contentType: UTType = .json) {
        self.data = data
        self.contentType = contentType
    }

    nonisolated func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<Data> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            FileWrapper(regularFileWithContents: snapshot)
        }
    }

    func snapshot(contentType: UTType) async throws -> sending Data {
        data
    }
}

extension UTType {
    /// Markdown, as the system declares it.
    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText
}
