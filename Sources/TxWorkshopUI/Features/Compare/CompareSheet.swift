import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import UniformTypeIdentifiers

/// Compares the document's transaction with another one, pasted or opened.
struct CompareSheet: View {
    let document: TxWorkshopDocument
    let current: TransactionInspection
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isImporting = false
    @State private var diff: LoadState<TransactionDiff> = .idle

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(TWFont.bytesSmall)
                        .frame(minHeight: 80, maxHeight: 140)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Text("Other transaction", bundle: #bundle))
                    Button {
                        compare(TxDocumentCodec.content(fromPastedText:), text)
                    } label: {
                        Text("Compare", bundle: #bundle)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || diff.isLoading)
                    Button {
                        isImporting = true
                    } label: {
                        Text("Open a File…", bundle: #bundle)
                    }
                } header: {
                    Text("Other transaction", bundle: #bundle)
                } footer: {
                    Text("Paste hex, base64 or a text envelope, or open a transaction file. Changes read from this document to the other.", bundle: #bundle)
                }
                switch diff {
                case .idle:
                    EmptyView()
                case .loading:
                    Section { ProgressView() }
                case .failed(let message):
                    Section {
                        Label {
                            Text(verbatim: message)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(TWColor.failure)
                    }
                case .loaded(let diff):
                    DiffSections(diff: diff)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Compare", bundle: #bundle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: #bundle)
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: TxWorkshopDocument.readableContentTypes) { result in
                guard case .success(let url) = result else { return }
                compare(Self.read, url)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 360, idealHeight: 600)
        #endif
    }

    /// Reads the other transaction with `read`, then inspects and compares
    /// it. Both use the document's network and chain data, so inputs and
    /// names they share read the same.
    private func compare<Source>(_ read: (Source) throws -> TxDocumentContent, _ source: Source) {
        let other: Data
        do {
            guard let bytes = try read(source).transaction else { throw TxDocumentError.empty }
            other = bytes
        } catch {
            diff = .failed(String(localized: "That is not a transaction in hex, base64, a text envelope or a transaction file.", bundle: #bundle))
            return
        }
        let network = document.content.network
        let chainContext = document.content.chainContext
        let current = current
        diff = .loading
        Task {
            do {
                let inspection = try await TransactionInspector().inspection(of: other, network: network, chainContext: chainContext)
                diff = .loaded(TransactionDiff(from: current, to: inspection))
            } catch {
                diff = .failed(String(describing: error))
            }
        }
    }

    /// The content of a transaction file or `.txworkshop` package.
    private static func read(_ url: URL) throws -> TxDocumentContent {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let wrapper = try FileWrapper(url: url)
        if wrapper.isDirectory {
            var files: [String: Data] = [:]
            for (name, child) in wrapper.fileWrappers ?? [:] {
                if let data = child.regularFileContents { files[name] = data }
            }
            return try TxDocumentCodec.content(fromPackageFiles: files)
        }
        guard let data = wrapper.regularFileContents,
            let type = UTType(filenameExtension: url.pathExtension),
            let format = TxDocumentFormat(contentType: type)
        else { throw TxDocumentError.empty }
        return try TxDocumentCodec.content(fromFile: data, format: format)
    }
}
