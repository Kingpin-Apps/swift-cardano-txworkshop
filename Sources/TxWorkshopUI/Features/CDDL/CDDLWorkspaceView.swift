import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Where the schema being read comes from.
enum SchemaSource: Hashable {
    case era(String)
    /// The document's own schema.
    case custom
}

/// Browse the bundled era schemas or edit the document's own: rules with
/// go-to-definition, parse errors, and formatting.
struct CDDLWorkspaceView: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var source: SchemaSource
    @State private var parsed: LoadState<CDDLSource> = .idle
    @State private var selectedRule: String?
    @State private var search = ""
    @State private var isEditing = false
    @State private var draft = ""
    @State private var showsSource = false

    init(document: TxWorkshopDocument, defaultEra: String) {
        self.document = document
        source = document.content.schema == nil ? .era(defaultEra) : .custom
    }

    /// The text being shown: a bundled schema, the saved custom schema, or
    /// the draft being edited.
    private var text: String {
        switch source {
        case .era(let era): (try? CDDLSource.bundled(era: era)) ?? ""
        case .custom: isEditing ? draft : document.content.schema ?? ""
        }
    }

    private struct ParseKey: Equatable {
        let source: SchemaSource
        let text: String
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .custom = source, document.content.schema == nil {
                NewSchemaView(document: document)
            } else if sizeClass == .compact {
                Picker(selection: $showsSource) {
                    Text("Rules", bundle: #bundle).tag(false)
                    Text("Source", bundle: #bundle).tag(true)
                } label: {
                    Text("Pane", bundle: #bundle)
                }
                .pickerStyle(.segmented)
                .padding(TWSpacing.s)
                if showsSource { sourcePane } else { ruleList }
            } else {
                HStack(spacing: 0) {
                    ruleList
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 340)
                    Divider()
                    sourcePane
                }
            }
        }
        .navigationTitle(Text("CDDL", bundle: #bundle))
        .toolbar { toolbar }
        .task(id: ParseKey(source: source, text: text)) {
            if isEditing {
                // Wait for typing to pause.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
            }
            let key = ParseKey(source: source, text: text)
            let bundledEra: String? = if case .era(let era) = source { era } else { nil }
            if parsed.value == nil { parsed = .loading }
            let result = await CDDLSource.parse(text, bundledEra: bundledEra)
            // Keep the result unless the schema changed meanwhile; a cancelled
            // task is not always restarted (as on iPhone).
            guard ParseKey(source: source, text: text) == key else { return }
            parsed = .loaded(result)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker(selection: $source) {
                ForEach(SchemaCheck.eras, id: \.self) { era in
                    Text(verbatim: era.capitalized).tag(SchemaSource.era(era))
                }
                Text("This Document's Schema", bundle: #bundle).tag(SchemaSource.custom)
            } label: {
                Text("Schema", bundle: #bundle)
            }
            .disabled(isEditing)
        }
        if case .custom = source, document.content.schema != nil {
            ToolbarItem {
                Button(action: format) {
                    Label {
                        Text("Format", bundle: #bundle)
                    } icon: {
                        Image(systemName: "text.alignleft")
                    }
                }
                .disabled(parsed.value?.formatted == nil)
            }
            ToolbarItem {
                Button(action: toggleEditing) {
                    if isEditing {
                        Text("Done", bundle: #bundle)
                    } else {
                        Text("Edit", bundle: #bundle)
                    }
                }
            }
        }
    }

    private var ruleList: some View {
        List(selection: $selectedRule) {
            if let schema = parsed.value {
                ForEach(filteredRules(schema)) { rule in
                    HStack {
                        Text(verbatim: rule.name)
                            .font(TWFont.bytesSmall)
                            .lineLimit(1)
                        Spacer()
                        Text("line \(rule.line)", bundle: #bundle)
                            .font(.caption)
                            .foregroundStyle(TWColor.secondaryText)
                    }
                    .tag(rule.id)
                }
            }
        }
        .searchable(text: $search, prompt: Text("Rules", bundle: #bundle))
        .overlay {
            if parsed.isLoading { ProgressView() }
        }
    }

    private func filteredRules(_ schema: CDDLSource) -> [CDDLSource.Rule] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? schema.rules : schema.rules.filter { $0.name.localizedStandardContains(query) }
    }

    @ViewBuilder private var sourcePane: some View {
        let schema = parsed.value
        let rule = schema?.rules.first { $0.id == selectedRule }
        VStack(spacing: 0) {
            if let problem = schema?.problem {
                Label {
                    Text("Line \(problem.line), column \(problem.column): \(problem.message)", bundle: #bundle)
                } icon: {
                    Image(systemName: "exclamationmark.octagon")
                }
                .labelStyle(.status(TWColor.failure))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(TWSpacing.s)
                .background(TWColor.failure.opacity(0.08))
            }
            if let rule, let schema, !isEditing {
                RuleLinks(rule: rule, usedBy: schema.usedBy(rule.name)) { name in
                    selectedRule = schema.definition(of: name)?.id
                    showsSource = true
                }
                Divider()
            }
            if isEditing {
                TextEditor(text: $draft)
                    .font(TWFont.bytesSmall)
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text("Schema", bundle: #bundle))
            } else {
                SourceLinesView(text: text, highlight: highlight(rule, in: schema), problemLine: schema?.problem?.line)
            }
        }
    }

    /// The lines of the selected rule: from its own line to the line before
    /// the next rule.
    private func highlight(_ rule: CDDLSource.Rule?, in schema: CDDLSource?) -> ClosedRange<Int>? {
        guard let rule, let schema else { return nil }
        let next = schema.rules.map(\.line).filter { $0 > rule.line }.min()
        return rule.line...max(rule.line, (next ?? rule.line + 1) - 1)
    }

    private func toggleEditing() {
        if isEditing {
            let edited = draft
            document.update({ $0.schema = edited }, actionName: LocalizedStringResource("Edit Schema", bundle: #bundle), undoManager: undoManager)
            isEditing = false
        } else {
            draft = document.content.schema ?? ""
            isEditing = true
        }
    }

    private func format() {
        guard let formatted = parsed.value?.formatted else { return }
        if isEditing {
            draft = formatted
        } else {
            document.update({ $0.schema = formatted }, actionName: LocalizedStringResource("Format Schema", bundle: #bundle), undoManager: undoManager)
        }
    }
}

/// Starts the document's own schema, from an era's or from nothing.
private struct NewSchemaView: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No schema of its own", bundle: #bundle)
            } icon: {
                Image(systemName: "text.book.closed")
            }
        } description: {
            Text("Write CDDL for this document, to check its CBOR against rules of your own. It is saved in the document.", bundle: #bundle)
        } actions: {
            Button {
                start(with: (try? CDDLSource.bundled(era: "conway")) ?? "")
            } label: {
                Text("Start from Conway", bundle: #bundle)
            }
            Button {
                start(with: "; Rules for this document.\n")
            } label: {
                Text("Start Empty", bundle: #bundle)
            }
        }
    }

    private func start(with text: String) {
        document.update({ $0.schema = text }, actionName: LocalizedStringResource("New Schema", bundle: #bundle), undoManager: undoManager)
    }
}
