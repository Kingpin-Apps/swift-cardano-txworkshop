import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The term being computed, the value being returned, or how the run ended.
struct DebugTermPane: View {
    let snapshot: DebugSnapshot
    let onShowFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.s) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: onShowFocus) {
                    Label {
                        Text("Show in Full", bundle: #bundle)
                    } icon: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .labelStyle(.iconOnly)
                    .twHitTarget()
                }
                .buttonStyle(.borderless)
                .disabled(!canShowFocus)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(verbatim: text)
                    .font(TWFont.bytesSmall)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, TWSpacing.m)
            }
            .accessibilityIdentifier("debugTerm")
        }
        .padding(TWSpacing.m)
    }

    private var title: LocalizedStringResource {
        switch snapshot.phase {
        case .computing: LocalizedStringResource("Computing", bundle: #bundle)
        case .returning: LocalizedStringResource("Returning", bundle: #bundle)
        case .finished: LocalizedStringResource("Result", bundle: #bundle)
        case .failed: LocalizedStringResource("Failed", bundle: #bundle)
        }
    }

    private var text: String {
        switch snapshot.phase {
        case .computing(let term): term
        case .returning(let value): value.summary
        case .finished(let result): result
        case .failed(let message): message
        }
    }

    private var canShowFocus: Bool {
        if case .failed = snapshot.phase { return false }
        return true
    }
}

/// The variables in scope, most recent first; one opens in full. A lazy
/// stack rather than a List: every step renumbers every row, and a List
/// takes about twice as long to redraw them.
struct DebugVariablesPane: View {
    let snapshot: DebugSnapshot
    let onShow: (DebugTarget) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    if snapshot.variables.isEmpty {
                        Text("None in scope here.", bundle: #bundle)
                            .foregroundStyle(TWColor.secondaryText)
                            .padding(.horizontal, TWSpacing.m)
                            .padding(.vertical, TWSpacing.s)
                    }
                    ForEach(snapshot.variables) { variable in
                        Button {
                            onShow(.variable(variable.index))
                        } label: {
                            VariableRow(variable: variable)
                                .padding(.horizontal, TWSpacing.m)
                                .padding(.vertical, TWSpacing.xs)
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, TWSpacing.m)
                    }
                } header: {
                    Text("Variables (\(snapshot.variables.count))", bundle: #bundle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TWColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TWSpacing.m)
                        .padding(.vertical, TWSpacing.s)
                        .background(.bar)
                }
            }
        }
        .accessibilityIdentifier("debugVariables")
    }
}

private struct VariableRow: View {
    let variable: DebugVariable

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TWSpacing.s) {
            Text(verbatim: variable.name)
                .font(TWFont.bytesSmall)
                .foregroundStyle(TWColor.secondaryText)
                .frame(minWidth: 36, alignment: .leading)
            if case .data(_, let label?) = variable.value {
                Text(verbatim: label)
                    .font(.caption.weight(.semibold))
            }
            Text(verbatim: summary)
                .font(TWFont.bytesSmall)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        if case .data(let shape, _) = variable.value { return shape }
        return variable.value.summary
    }
}

/// The work still to do, innermost first.
struct DebugStackPane: View {
    let snapshot: DebugSnapshot

    var body: some View {
        List {
            Section {
                if snapshot.frames.isEmpty {
                    Text("Empty: this is the top of the program.", bundle: #bundle)
                        .foregroundStyle(TWColor.secondaryText)
                }
                ForEach(snapshot.frames) { frame in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: frame.title)
                        if let detail = frame.detail {
                            Text(verbatim: detail)
                                .font(TWFont.bytesSmall)
                                .foregroundStyle(TWColor.secondaryText)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Stack (\(snapshot.frames.count))", bundle: #bundle)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("debugStack")
    }
}

/// What the last step did, then the traces so far.
struct DebugLogPane: View {
    let snapshot: DebugSnapshot

    var body: some View {
        List {
            if !snapshot.events.isEmpty {
                Section {
                    ForEach(snapshot.events.enumerated(), id: \.offset) { _, event in
                        Text(verbatim: event)
                            .font(TWFont.bytesSmall)
                    }
                } header: {
                    Text("This step", bundle: #bundle)
                }
            }
            Section {
                if snapshot.logs.isEmpty {
                    Text("No traces yet.", bundle: #bundle)
                        .foregroundStyle(TWColor.secondaryText)
                }
                ForEach(snapshot.logs.enumerated().reversed(), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(TWFont.bytesSmall)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Traces (\(snapshot.logs.count))", bundle: #bundle)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("debugLog")
    }
}

/// A variable or the current value in full: data as a tree, code as text.
struct DebugDetailSheet: View {
    let debugger: ScriptDebugger
    let target: DebugTarget
    @Environment(\.dismiss) private var dismiss
    @State private var detail: LoadState<DebugDetail> = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch detail {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Text("Nothing to Show", bundle: #bundle)
                    } description: {
                        Text(verbatim: message)
                    }
                case .loaded(.tree(let node, _)):
                    List {
                        DataTreeView(node: node)
                    }
                case .loaded(.text(let text)):
                    ScrollView([.vertical, .horizontal]) {
                        Text(verbatim: text)
                            .font(TWFont.bytesSmall)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(TWSpacing.m)
                    }
                }
            }
            .navigationTitle(title)
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                }
            }
            .task {
                if let loaded = await debugger.detail(target) {
                    detail = .loaded(loaded)
                } else {
                    detail = .failed(String(localized: "It is not in scope at this step.", bundle: #bundle))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 420, idealHeight: 600)
        #endif
    }

    private var title: Text {
        switch (target, detail) {
        case (_, .loaded(.tree(_, let label?))): Text(verbatim: label)
        case (.variable(let index), _): Text(verbatim: "#\(index)")
        case (.focus, _): Text("Current Value", bundle: #bundle)
        }
    }
}
