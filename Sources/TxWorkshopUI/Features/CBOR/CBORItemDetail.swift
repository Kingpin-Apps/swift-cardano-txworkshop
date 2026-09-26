import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Everything about the selected item: where it was written, how it departs
/// from canonical CBOR, and its diagnostic notation.
struct CBORItemDetail: View {
    let exploration: CBORExploration
    let item: CBORItem
    @State private var diagnostic: String?

    var body: some View {
        Form {
            Section {
                if let name = item.name {
                    TWFieldRow(LocalizedStringResource("Field", bundle: #bundle)) { Text(verbatim: name) }
                }
                TWFieldRow(LocalizedStringResource("Kind", bundle: #bundle)) { Text(item.kindSummary) }
                TWFieldRow(LocalizedStringResource("Bytes", bundle: #bundle)) {
                    Text("\(item.start)–\(item.end) (\(item.byteCount))", bundle: #bundle)
                        .font(TWFont.figure)
                }
                TWFieldRow(LocalizedStringResource("Head", bundle: #bundle)) {
                    Text("\(item.start)–\(item.headerEnd)", bundle: #bundle)
                        .font(TWFont.figure)
                }
                if let keyRange = item.keyRange {
                    TWFieldRow(LocalizedStringResource("Key bytes", bundle: #bundle)) {
                        Text("\(keyRange.lowerBound)–\(keyRange.upperBound)", bundle: #bundle)
                            .font(TWFont.figure)
                    }
                }
                if !item.isComplete {
                    Label {
                        Text("The bytes end before this item does.", bundle: #bundle)
                    } icon: {
                        Image(systemName: "exclamationmark.octagon")
                    }
                    .foregroundStyle(TWColor.failure)
                }
                if item.childrenOmitted {
                    Text("Nested too deep to show as a tree; the notation below has it all.", bundle: #bundle)
                        .foregroundStyle(TWColor.secondaryText)
                }
            } header: {
                Text(verbatim: item.label ?? String(localized: "Root", bundle: #bundle))
            }
            if !item.flags.isEmpty {
                Section {
                    ForEach(item.flags, id: \.self) { flag in
                        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                            Text(flag.title)
                            Text(flag.explanation)
                                .font(.caption)
                                .foregroundStyle(TWColor.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Not canonical", bundle: #bundle)
                }
            }
            Section {
                if let diagnostic {
                    ScrollView([.horizontal, .vertical]) {
                        Text(verbatim: diagnostic)
                            .font(TWFont.bytesSmall)
                            .textSelection(.enabled)
                            .fixedSize()
                    }
                    .frame(maxHeight: 360)
                } else {
                    ProgressView()
                }
            } header: {
                Text("Diagnostic notation", bundle: #bundle)
            }
        }
        .formStyle(.grouped)
        .task(id: [exploration.id.uuidString, item.id]) {
            diagnostic = nil
            diagnostic = await exploration.diagnosticText(at: item.path)
        }
    }
}
