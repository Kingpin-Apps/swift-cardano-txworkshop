import SwiftUI
import TxWorkshopCore

/// Free-form notes, saved with the document. Edits are kept locally and
/// written to the document as they change, so each is registered for undo;
/// an undo that changes the document's notes flows back into the field.
struct NotesSection: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager
    @State private var notes = ""

    var body: some View {
        Section {
            TextField(text: $notes, axis: .vertical) {
                Text("Add notes", bundle: #bundle)
            }
            .lineLimit(4...)
            .labelsHidden()
        } header: {
            Text("Notes", bundle: #bundle)
        }
        .onAppear { notes = document.content.notes }
        .onChange(of: notes) { _, newValue in
            guard newValue != document.content.notes else { return }
            document.update(
                { $0.notes = newValue },
                actionName: LocalizedStringResource("Edit Notes", bundle: #bundle),
                undoManager: undoManager
            )
        }
        .onChange(of: document.content.notes) { _, newValue in
            if newValue != notes { notes = newValue }
        }
    }
}
