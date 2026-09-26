import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// An item and, when it is expanded, the items inside it.
struct CBORTreeRow: View {
    let item: CBORItem
    let markers: CBORMarkers
    @Binding var expanded: Set<String>

    var body: some View {
        if let children = item.children, !children.isEmpty {
            DisclosureGroup(isExpanded: $expanded.contains(item.id)) {
                ForEach(children) { child in
                    CBORTreeRow(item: child, markers: markers, expanded: $expanded)
                }
            } label: {
                CBORItemLabel(item: item, mark: markers.mark(item.id), holdsMark: markers.contains(item.id))
            }
            .tag(item.id)
        } else {
            CBORItemLabel(item: item, mark: markers.mark(item.id), holdsMark: false)
                .tag(item.id)
        }
    }
}

/// The one-line description of an item in the tree.
struct CBORItemLabel: View {
    let item: CBORItem
    /// A validation finding on the item: `true` for an error.
    let mark: Bool?
    /// Whether an item inside this one has a finding.
    let holdsMark: Bool

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
            if let mark {
                Image(systemName: mark ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(mark ? TWColor.failure : TWColor.warning)
                    .accessibilityLabel(mark ? Text("Validation error", bundle: #bundle) : Text("Validation warning", bundle: #bundle))
            } else if holdsMark {
                Circle()
                    .fill(TWColor.failure.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(Text("Contains a validation finding", bundle: #bundle))
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
