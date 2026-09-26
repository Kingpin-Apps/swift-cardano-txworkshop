import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The transaction's bytes as a CBOR tree beside its hex, linked both ways.
struct CBORExplorerView: View {
    let document: TxWorkshopDocument
    @State private var exploration: LoadState<CBORExploration> = .idle

    var body: some View {
        Group {
            switch exploration {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label {
                        Text("No CBOR", bundle: #bundle)
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                } description: {
                    Text(verbatim: message)
                }
            case .loaded(let exploration):
                CBORWorkspace(exploration: exploration)
            }
        }
        .navigationTitle(Text("CBOR", bundle: #bundle))
        .task(id: document.content.transaction) {
            guard let bytes = document.content.transaction else {
                exploration = .failed(String(localized: "The document has no transaction yet.", bundle: #bundle))
                return
            }
            if exploration.value == nil { exploration = .loading }
            let explored = await CBORExploration.explore(bytes)
            guard !Task.isCancelled else { return }
            exploration = .loaded(explored)
        }
    }
}

/// The tree, hex and detail for one exploration.
private struct CBORWorkspace: View {
    let exploration: CBORExploration
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: String?
    @State private var expanded: Set<String> = [""]
    @State private var pane = Pane.tree

    enum Pane: Hashable { case tree, hex, detail }

    private var selectedItem: CBORItem? {
        selection.flatMap { exploration.item(at: CBORItem.path(fromID: $0)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = exploration.problem {
                ProblemBanner(problem: problem) { offset in select(byte: offset) }
            }
            if sizeClass == .compact {
                Picker(selection: $pane) {
                    Text("Tree", bundle: #bundle).tag(Pane.tree)
                    Text("Hex", bundle: #bundle).tag(Pane.hex)
                    Text("Detail", bundle: #bundle).tag(Pane.detail)
                } label: {
                    Text("Pane", bundle: #bundle)
                }
                .pickerStyle(.segmented)
                .padding(TWSpacing.s)
                switch pane {
                case .tree: tree
                case .hex: hex
                case .detail: detail
                }
            } else {
                HStack(spacing: 0) {
                    tree
                        .frame(minWidth: 280, idealWidth: 380)
                    Divider()
                    VStack(spacing: 0) {
                        hex
                            .frame(minHeight: 160)
                        Divider()
                        detail
                    }
                    .frame(minWidth: 320)
                }
            }
        }
    }

    private var tree: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                if let root = exploration.root {
                    CBORTreeRow(item: root, expanded: $expanded)
                }
            }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id) }
            }
        }
    }

    private var hex: some View {
        HexView(
            bytes: exploration.bytes, selection: selectedItem,
            problemOffset: exploration.problem?.offset, onSelectByte: select(byte:)
        )
    }

    @ViewBuilder private var detail: some View {
        if let item = selectedItem {
            CBORItemDetail(exploration: exploration, item: item)
        } else {
            ContentUnavailableView {
                Text("Select an item", bundle: #bundle)
            } description: {
                Text("Pick an item in the tree, or tap a byte.", bundle: #bundle)
            }
        }
    }

    /// Selects the item a byte belongs to, opening the tree down to it.
    private func select(byte offset: Int) {
        guard var path = exploration.path(toByte: offset) else { return }
        // The tree stops at its depth limit.
        path = Array(path.prefix(CBORItem.maxDepth))
        expanded.formUnion(CBORItem.ancestorIDs(of: path))
        selection = path.map(String.init).joined(separator: ".")
        if sizeClass == .compact, pane == .hex { pane = .detail }
    }
}

/// Where and why decoding stopped.
private struct ProblemBanner: View {
    let problem: CBORExploration.Problem
    let onSelect: (Int) -> Void

    var body: some View {
        HStack {
            Label {
                if let offset = problem.offset {
                    Text("Decoding stopped at byte \(offset): \(problem.message)", bundle: #bundle)
                } else {
                    Text("Decoding stopped: \(problem.message)", bundle: #bundle)
                }
            } icon: {
                Image(systemName: "exclamationmark.octagon")
            }
            .foregroundStyle(TWColor.failure)
            Spacer()
            if let offset = problem.offset {
                Button {
                    onSelect(offset)
                } label: {
                    Text("Show", bundle: #bundle)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(TWSpacing.s)
        .background(TWColor.failure.opacity(0.08))
    }
}
