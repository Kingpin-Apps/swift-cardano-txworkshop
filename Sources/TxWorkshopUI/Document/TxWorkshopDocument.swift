import Foundation
import SwiftUI
import TxWorkshopCore
import UniformTypeIdentifiers

/// An open Tx Workshop document.
///
/// Opens its own `.txworkshop` package and bare transactions — text envelopes,
/// raw CBOR and hex — and saves back to whichever it was opened from. Every
/// change goes through ``update(_:actionName:undoManager:)``, which registers
/// an undo action: SwiftUI detects unsaved changes from the undo stack, so a
/// change made without one would never be autosaved.
@MainActor
@Observable
public final class TxWorkshopDocument: Document {
    public nonisolated static let readableContentTypes: [UTType] = TxDocumentFormat.allCases.map(\.contentType)
    public nonisolated static let writableContentTypes: [UTType] = TxDocumentFormat.allCases.map(\.contentType)

    public private(set) var content: TxDocumentContent

    public init(content: TxDocumentContent = TxDocumentContent()) {
        self.content = content
    }

    /// Changes the content and registers the change with `undoManager`, so it
    /// can be undone, redone, and is autosaved.
    public func update(
        _ change: (inout TxDocumentContent) -> Void,
        actionName: LocalizedStringResource,
        undoManager: UndoManager?
    ) {
        var changed = content
        change(&changed)
        replaceContent(with: changed, actionName: actionName, undoManager: undoManager)
    }

    private func replaceContent(
        with newContent: TxDocumentContent,
        actionName: LocalizedStringResource,
        undoManager: UndoManager?
    ) {
        guard newContent != content else { return }
        let previous = content
        content = newContent
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.replaceContent(with: previous, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager?.setActionName(String(localized: actionName))
    }

    // MARK: Reading

    public nonisolated func reader(
        configuration: sending ReadConfiguration
    ) -> sending FileWrapperDocumentReader<TxDocumentContent> {
        let format = TxDocumentFormat(contentType: configuration.contentType)
        return FileWrapperDocumentReader(configuration) { fileWrapper in
            guard let format else { throw CocoaError(.fileReadUnsupportedScheme) }
            if format == .package {
                var files: [String: Data] = [:]
                for (name, child) in fileWrapper.fileWrappers ?? [:] {
                    if let data = child.regularFileContents { files[name] = data }
                }
                return try TxDocumentCodec.content(fromPackageFiles: files)
            }
            guard let data = fileWrapper.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            return try TxDocumentCodec.content(fromFile: data, format: format)
        }
    }

    public func apply(snapshot: sending TxDocumentContent, previous: sending TxDocumentContent?) async throws {
        content = snapshot
    }

    // MARK: Writing

    public nonisolated func writer(
        configuration: sending WriteConfiguration
    ) -> sending FileWrapperDocumentWriter<TxDocumentContent> {
        let format = TxDocumentFormat(contentType: configuration.contentType)
        return FileWrapperDocumentWriter(configuration) { snapshot, _ in
            guard let format else { throw CocoaError(.fileWriteUnsupportedScheme) }
            if format == .package {
                let directory = FileWrapper(directoryWithFileWrappers: [:])
                for (name, data) in try TxDocumentCodec.packageFiles(for: snapshot) {
                    let file = FileWrapper(regularFileWithContents: data)
                    file.preferredFilename = name
                    directory.addFileWrapper(file)
                }
                return directory
            }
            return FileWrapper(regularFileWithContents: try TxDocumentCodec.file(for: snapshot, format: format))
        }
    }

    public func snapshot(contentType: UTType) async throws -> sending TxDocumentContent {
        content
    }
}
