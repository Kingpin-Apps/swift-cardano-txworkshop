import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The transaction's bytes as a CBOR tree beside its hex, linked both ways.
struct CBORExplorerView: View {
    let document: TxWorkshopDocument
    /// The era the schema check starts with.
    let defaultEra: String
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
                CBORWorkspace(document: document, exploration: exploration, era: defaultEra)
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
            // Keep the result unless the document has changed since; on
            // iPhone the push can cancel this task without starting another.
            guard explored.bytes == document.content.transaction else { return }
            exploration = .loaded(explored)
        }
    }
}

/// The tree, hex and detail for one exploration.
private struct CBORWorkspace: View {
    let document: TxWorkshopDocument
    let exploration: CBORExploration
    @State private var era: String
    @State private var editing: HexEditRequest?
    @State private var markers = CBORMarkers.none
    @Environment(\.undoManager) private var undoManager
    @Environment(WorkshopSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: String?
    @State private var expanded: Set<String> = [""]
    @State private var pane = Pane.tree
    @State private var inspector = Inspector.item
    /// Too narrow for the tree beside the hex, as in a slim iPad window.
    @State private var isNarrow = false

    enum Pane: Hashable { case tree, hex, detail, schema }
    enum Inspector: Hashable { case item, schema }

    init(document: TxWorkshopDocument, exploration: CBORExploration, era: String) {
        self.document = document
        self.exploration = exploration
        self.era = era
    }

    private var selectedItem: CBORItem? {
        selection.flatMap { exploration.item(at: CBORItem.path(fromID: $0)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = exploration.problem {
                ProblemBanner(problem: problem) { offset in select(byte: offset) }
            }
            if sizeClass == .compact || isNarrow {
                Picker(selection: $pane) {
                    Text("Tree", bundle: #bundle).tag(Pane.tree)
                    Text("Hex", bundle: #bundle).tag(Pane.hex)
                    Text("Detail", bundle: #bundle).tag(Pane.detail)
                    Text("Schema", bundle: #bundle).tag(Pane.schema)
                } label: {
                    Text("Pane", bundle: #bundle)
                }
                .pickerStyle(.segmented)
                .padding(TWSpacing.s)
                switch pane {
                case .tree: tree
                case .hex: hex
                case .detail: detail
                case .schema: schema
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
                        Picker(selection: $inspector) {
                            Text("Item", bundle: #bundle).tag(Inspector.item)
                            Text("Schema", bundle: #bundle).tag(Inspector.schema)
                        } label: {
                            Text("Inspector", bundle: #bundle)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(TWSpacing.s)
                        switch inspector {
                        case .item: detail
                        case .schema: schema
                        }
                    }
                    .frame(minWidth: 320)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 640 } action: { isNarrow = $0 }
        .toolbar {
            ToolbarItem {
                Button {
                    editing = editRequest()
                } label: {
                    Label {
                        if selectedItem == nil {
                            Text("Edit All Bytes…", bundle: #bundle)
                        } else {
                            Text("Edit Selected Bytes…", bundle: #bundle)
                        }
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .task(id: MarkerKey(exploration: exploration.id, validated: session.validation(for: exploration.bytes)?.ranAt)) {
            markers = CBORMarkers(outcome: session.validation(for: exploration.bytes), exploration: exploration)
        }
        .onChange(of: session.cborFieldFocus, initial: true) { _, fieldPath in
            guard let fieldPath else { return }
            session.cborFieldFocus = nil
            if let path = exploration.path(forFieldPath: fieldPath) {
                select(path: path)
                inspector = .item
                if sizeClass == .compact { pane = .detail }
            }
        }
        .sheet(item: $editing) { request in
            HexEditSheet(document: document, request: request, undoManager: undoManager)
        }
    }

    private struct MarkerKey: Equatable {
        let exploration: UUID
        let validated: Date?
    }

    /// The selected item's bytes, or all of them.
    private func editRequest() -> HexEditRequest {
        let first = exploration.root?.children?.first
        let body = first?.name == "transaction body" ? first?.range : nil
        if let item = selectedItem {
            return HexEditRequest(range: item.range, title: item.name ?? item.label, bodyRange: body)
        }
        return HexEditRequest(range: 0..<exploration.bytes.count, title: nil, bodyRange: body)
    }

    private var tree: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                if let root = exploration.root {
                    CBORTreeRow(item: root, markers: markers, selection: selection, expanded: $expanded)
                }
            }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(id) }
            }
        }
    }

    private var hex: some View {
        HexView(
            bytes: exploration.bytes, selection: selectedItem,
            problemOffset: exploration.problem?.offset, markers: markers, onSelectByte: select(byte:)
        )
    }

    @ViewBuilder private var detail: some View {
        if let item = selectedItem {
            CBORItemDetail(exploration: exploration, item: item, findings: markers.findings(item.id))
        } else {
            ContentUnavailableView {
                Text("Select an item", bundle: #bundle)
            } description: {
                Text("Pick an item in the tree, or tap a byte.", bundle: #bundle)
            }
        }
    }

    private var schema: some View {
        SchemaPanel(
            exploration: exploration, selectedItem: selectedItem, onSelectPath: select(path:),
            customSchema: document.content.schema, era: $era
        )
    }

    /// Selects the item a byte belongs to, opening the tree down to it.
    private func select(byte offset: Int) {
        guard let path = exploration.path(toByte: offset) else { return }
        select(path: path)
        if sizeClass == .compact, pane == .hex { pane = .detail }
    }

    private func select(path: [Int]) {
        // The tree stops at its depth limit.
        let path = Array(path.prefix(CBORItem.maxDepth))
        expanded.formUnion(CBORItem.ancestorIDs(of: path))
        selection = path.map(String.init).joined(separator: ".")
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
            .labelStyle(.status(TWColor.failure))
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
