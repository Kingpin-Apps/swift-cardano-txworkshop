import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// What to edit: a run of the transaction's bytes.
struct HexEditRequest: Identifiable {
    let range: Range<Int>
    /// The item being edited, or `nil` for the whole transaction.
    let title: String?
    /// The transaction body's bytes; editing them changes the id.
    let bodyRange: Range<Int>?
    var id: String { "\(range.lowerBound)-\(range.upperBound)" }
}

/// Edits bytes as hex, checks the result decodes, and splices it back into
/// the document as one undoable change.
struct HexEditSheet: View {
    let document: TxWorkshopDocument
    let request: HexEditRequest
    /// The document window's undo manager. On macOS a sheet is a window of
    /// its own, whose undo manager is not the document's.
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var check: Check = .unchanged

    enum Check: Equatable {
        case unchanged
        case notHex
        case decodes(byteCount: Int)
        case stops(offset: Int?, message: String)
    }

    init(document: TxWorkshopDocument, request: HexEditRequest, undoManager: UndoManager?) {
        self.document = document
        self.request = request
        self.undoManager = undoManager
        let bytes = document.content.transaction ?? Data()
        let slice = bytes.dropFirst(request.range.lowerBound).prefix(request.range.count)
        // Thirty-two bytes to a line.
        let hex = slice.map { String(format: "%02x", $0) }.joined()
        text = stride(from: 0, to: hex.count, by: 64).map { start in
            let from = hex.index(hex.startIndex, offsetBy: start)
            return String(hex[from..<(hex.index(from, offsetBy: 64, limitedBy: hex.endIndex) ?? hex.endIndex)])
        }.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(TWFont.bytesSmall)
                        .frame(minHeight: 120, maxHeight: 320)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Text("Bytes in hex", bundle: #bundle))
                } header: {
                    Text("Bytes \(request.range.lowerBound)–\(request.range.upperBound)", bundle: #bundle)
                } footer: {
                    if let bodyRange = request.bodyRange, bodyRange.overlaps(request.range) {
                        Text("These bytes are part of the transaction body: changing them changes the transaction id, and existing signatures no longer match.", bundle: #bundle)
                    }
                }
                Section {
                    CheckLabel(check: check)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Edit Bytes", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: apply) { Text("Apply", bundle: #bundle) }
                        .disabled(!canApply)
                }
            }
            .task(id: text) { await recheck() }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 360, idealHeight: 480)
        #endif
    }

    private var canApply: Bool {
        switch check {
        case .unchanged, .notHex: false
        case .decodes, .stops: true
        }
    }

    /// The document's bytes with the edit spliced in, or `nil` when the text
    /// is not hex.
    private func edited() -> Data? {
        let digits = text.filter { !$0.isWhitespace }
        let replacement: Data
        if digits.isEmpty {
            replacement = Data()
        } else if let parsed = try? TxDocumentCodec.bytes(fromHex: digits) {
            replacement = parsed
        } else {
            return nil
        }
        var bytes = document.content.transaction ?? Data()
        let start = bytes.startIndex + request.range.lowerBound
        bytes.replaceSubrange(start..<(start + request.range.count), with: replacement)
        return bytes
    }

    private func recheck() async {
        // Wait for typing to pause.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        guard let bytes = edited() else {
            check = .notHex
            return
        }
        guard bytes != document.content.transaction else {
            check = .unchanged
            return
        }
        let exploration = await CBORExploration.explore(bytes)
        guard !Task.isCancelled else { return }
        if let problem = exploration.problem {
            check = .stops(offset: problem.offset, message: problem.message)
        } else {
            check = .decodes(byteCount: bytes.count)
        }
    }

    private func apply() {
        guard let bytes = edited() else { return }
        document.update(
            { $0.transaction = bytes },
            actionName: LocalizedStringResource("Edit Bytes", bundle: #bundle),
            undoManager: undoManager
        )
        dismiss()
    }
}

private struct CheckLabel: View {
    let check: HexEditSheet.Check

    var body: some View {
        switch check {
        case .unchanged:
            Text("No changes yet.", bundle: #bundle)
                .foregroundStyle(TWColor.secondaryText)
        case .notHex:
            Label {
                Text("Not hex: use pairs of 0–9 and a–f.", bundle: #bundle)
            } icon: {
                Image(systemName: "xmark.octagon")
            }
            .labelStyle(.status(TWColor.failure))
        case .decodes(let count):
            Label {
                Text(AttributedString(localized: "Decodes as one CBOR item of ^[\(count) byte](inflect: true).", bundle: #bundle))
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .labelStyle(.status(TWColor.success))
        case .stops(let offset, let message):
            Label {
                if let offset {
                    Text("Decoding would stop at byte \(offset): \(message). You can still apply it and fix it in the tree.", bundle: #bundle)
                } else {
                    Text("Decoding would stop: \(message). You can still apply it and fix it in the tree.", bundle: #bundle)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .labelStyle(.status(TWColor.warning))
        }
    }
}
