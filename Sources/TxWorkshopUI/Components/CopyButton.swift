import SwiftCardanoExplorers
import SwiftUI
import TxWorkshopCore

/// Copies a value, such as an address, a transaction id or a hash, to the
/// clipboard, and shows a tick for a moment once it has.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            Clipboard.copy(text)
            copied = true
        } label: {
            Label {
                copied ? Text("Copied", bundle: #bundle) : Text("Copy", bundle: #bundle)
            } icon: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .labelStyle(.iconOnly)
            .twHitTarget()
        }
        .buttonStyle(.borderless)
        .help(Text("Copy", bundle: #bundle))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// An address, id or hash, with a button to copy it and, when given, one to
/// open it in the chosen block explorer.
struct CopyableBytes: View {
    let text: String
    var font: Font = TWFont.bytesSmall
    var item: ExplorerItem? = nil

    init(_ text: String, font: Font = TWFont.bytesSmall, item: ExplorerItem? = nil) {
        self.text = text
        self.font = font
        self.item = item
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TWBytesText(text, font: font)
            CopyButton(text: text)
            if let item {
                ExplorerLinkButton(item: item)
            }
        }
    }
}
