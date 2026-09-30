import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Plutus data or metadata as an expandable tree.
struct DataTreeView: View {
    let node: DataNode

    var body: some View {
        DataNodeRow(node: node, isRoot: true)
    }
}

private struct DataNodeRow: View {
    let node: DataNode
    var isRoot = false
    @State private var isExpanded: Bool

    init(node: DataNode, isRoot: Bool = false) {
        self.node = node
        self.isRoot = isRoot
        self.isExpanded = isRoot
    }

    /// How far each level sits in from its parent. The Mac's disclosure
    /// groups indent their content already; iOS and visionOS do not.
    #if os(macOS)
    private static let childIndent: CGFloat = 0
    #else
    private static let childIndent: CGFloat = TWSpacing.l
    #endif

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    DataNodeRow(node: child)
                        .padding(.leading, Self.childIndent)
                }
            } label: {
                NodeLabel(node: node)
            }
        } else {
            NodeLabel(node: node)
        }
    }
}

private struct NodeLabel: View {
    let node: DataNode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TWSpacing.s) {
            if !node.label.isEmpty {
                Text(verbatim: node.label)
                    .font(TWFont.bytesSmall)
                    .foregroundStyle(TWColor.secondaryText)
            }
            Text(verbatim: node.summary)
                .font(TWFont.bytesSmall)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
