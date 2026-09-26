import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// An item and, when it is expanded, the items inside it.
struct CBORTreeRow: View {
    let item: CBORItem
    @Binding var expanded: Set<String>

    var body: some View {
        if let children = item.children, !children.isEmpty {
            DisclosureGroup(isExpanded: $expanded.contains(item.id)) {
                ForEach(children) { child in
                    CBORTreeRow(item: child, expanded: $expanded)
                }
            } label: {
                CBORItemLabel(item: item)
            }
            .tag(item.id)
        } else {
            CBORItemLabel(item: item)
                .tag(item.id)
        }
    }
}

/// The one-line description of an item in the tree.
struct CBORItemLabel: View {
    let item: CBORItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TWSpacing.s) {
            if let label = item.label {
                Text(verbatim: label)
                    .font(TWFont.bytesSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                if let name = item.name {
                    Text(verbatim: name)
                        .fontWeight(.medium)
                }
                Text(item.kindSummary)
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
            }
            Spacer(minLength: TWSpacing.s)
            if let preview = item.preview {
                Text(verbatim: preview)
                    .font(TWFont.bytesSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !item.isComplete {
                Image(systemName: "exclamationmark.octagon")
                    .foregroundStyle(TWColor.failure)
                    .accessibilityLabel(Text("Incomplete", bundle: #bundle))
            } else if !item.flags.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(TWColor.warning)
                    .accessibilityLabel(Text("Not canonical", bundle: #bundle))
            }
        }
    }
}
