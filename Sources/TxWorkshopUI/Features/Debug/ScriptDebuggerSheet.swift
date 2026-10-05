import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Identifies the redeemer whose script to debug.
struct DebugRequest: Identifiable {
    let position: Int
    /// Open at the step the run fails at.
    var atFailure = false
    var id: Int { position }
}

/// Steps through one redeemer's script run: the term being computed, the
/// variables in scope, the stack, the budget and the traces, with stepping
/// back, step over and out, breakpoints and a timeline to scrub.
struct ScriptDebuggerSheet: View {
    let document: TxWorkshopDocument
    let request: DebugRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(BlueprintLibrary.self) private var library
    @State private var debugger: ScriptDebugger?
    @State private var snapshot: DebugSnapshot?
    @State private var problem: String?
    /// A command is running. Not read by the body, so setting it does not
    /// redraw the debugger.
    @State private var isRunning = false
    /// A command has run long enough to show the controls as busy.
    @State private var isBusy = false
    @State private var breakpoints: Set<DebugBreakpoint> = [.failure]
    @State private var scrub: Double = 0
    @State private var isScrubbing = false
    @State private var pane = DebugPane.term
    @State private var detail: DebugTarget?
    /// A redeemer to run with instead of the transaction's: a what-if.
    @State private var redeemerOverride: String?
    @State private var isEditingRedeemer = false
    @State private var blueprints: [StoredBlueprint] = []

    var body: some View {
        NavigationStack {
            Group {
                if let debugger, let snapshot {
                    content(debugger, snapshot)
                } else if let problem {
                    ContentUnavailableView {
                        Text("Cannot Debug", bundle: #bundle)
                    } description: {
                        Text(verbatim: problem)
                    } actions: {
                        FetchChainDataButton(document: document) {
                            Task { await open() }
                        }
                    }
                } else {
                    ProgressView {
                        Text("Running the script once…", bundle: #bundle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(Text("Script Debugger", bundle: #bundle))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                }
                ToolbarItem {
                    Button {
                        isEditingRedeemer = true
                    } label: {
                        Label {
                            Text("Edit Redeemer", bundle: #bundle)
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    .disabled(debugger == nil)
                    .accessibilityIdentifier("debugEditRedeemer")
                }
            }
            .task { await open() }
            .sheet(isPresented: $isEditingRedeemer) {
                if let debugger {
                    RedeemerEditSheet(hex: debugger.redeemerHex, form: debugger.redeemerForm, blueprints: blueprints) { hex in
                        Task { await open(redeemer: hex) }
                    }
                }
            }
            .sheet(item: $detail) { target in
                if let debugger {
                    DebugDetailSheet(debugger: debugger, target: target)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 820, idealWidth: 1040, minHeight: 600, idealHeight: 780)
        #endif
    }

    // MARK: - Layout

    @ViewBuilder private func content(_ debugger: ScriptDebugger, _ snapshot: DebugSnapshot) -> some View {
        VStack(spacing: 0) {
            // A rerun that could not start keeps the last session on screen.
            if let problem {
                TWErrorText(problem)
                    .padding(.horizontal, TWSpacing.m)
                    .padding(.top, TWSpacing.s)
                    .accessibilityIdentifier("debugProblem")
            }
            if redeemerOverride != nil {
                HStack {
                    Label {
                        Text("Running with an edited redeemer. The transaction is unchanged.", bundle: #bundle)
                    } icon: {
                        Image(systemName: "pencil.circle")
                    }
                    .labelStyle(.status(TWColor.warning))
                    .font(.caption)
                    Spacer()
                    Button {
                        Task { await open(redeemer: nil) }
                    } label: {
                        Text("Reset", bundle: #bundle)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("debugResetRedeemer")
                }
                .padding(.horizontal, TWSpacing.m)
                .padding(.top, TWSpacing.s)
            }
            DebugControls(
                end: debugger.end, snapshot: snapshot, isBusy: isBusy, breakpoints: $breakpoints,
                scrub: $scrub, isScrubbing: $isScrubbing, perform: perform
            )
            Divider()
            if sizeClass == .compact {
                Picker(selection: $pane) {
                    ForEach(DebugPane.allCases) { pane in
                        Text(pane.title).tag(pane)
                    }
                } label: {
                    Text("Pane", bundle: #bundle)
                }
                .pickerStyle(.segmented)
                .padding(TWSpacing.s)
                Group {
                    switch pane {
                    case .term: DebugTermPane(snapshot: snapshot) { detail = .focus }
                    case .variables: DebugVariablesPane(snapshot: snapshot) { detail = $0 }
                    case .stack: DebugStackPane(snapshot: snapshot)
                    case .log: DebugLogPane(snapshot: snapshot)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    DebugTermPane(snapshot: snapshot) { detail = .focus }
                        .frame(maxWidth: .infinity)
                    Divider()
                    VStack(spacing: 0) {
                        DebugVariablesPane(snapshot: snapshot) { detail = $0 }
                        Divider()
                        DebugStackPane(snapshot: snapshot)
                    }
                    .frame(maxWidth: 420)
                }
                .frame(maxHeight: .infinity)
                Divider()
                DebugLogPane(snapshot: snapshot)
                    .frame(height: 150)
            }
        }
    }

    // MARK: - Running

    /// Opens the session, with `redeemer` (CBOR hex) in place of the
    /// transaction's when given.
    private func open(redeemer: String? = nil) async {
        if redeemer == nil, redeemerOverride == nil, debugger != nil { return }
        guard let bytes = document.content.transaction, let chain = document.content.chainContext else {
            problem = String(localized: "Fetch or enter chain data first: the script needs the inputs it spends and the protocol parameters.", bundle: #bundle)
            return
        }
        problem = nil
        let kept = document.content.recipe?.blueprints ?? []
        let every = kept + library.blueprints.filter { stored in !kept.contains { $0.id == stored.id } }
        blueprints = every
        let applied = document.content.recipe.map(BlueprintCatalog.appliedScripts(in:)) ?? [:]
        do {
            let opened = try await ScriptDebugger.open(
                bytes, position: request.position, snapshot: chain, network: document.content.network,
                blueprints: every, applied: applied, redeemer: redeemer
            )
            let first = request.atFailure && opened.end.failure != nil ? await opened.perform(.toFailure) : await opened.snapshot()
            snapshot = first
            scrub = Double(first.step)
            debugger = opened
            redeemerOverride = redeemer
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }

    /// Runs `command`. Most take a few milliseconds, so the controls show as
    /// busy only for a slow one: a step then draws the debugger once, not
    /// three times.
    private func perform(_ command: DebugCommand) {
        guard let debugger, !isRunning else { return }
        isRunning = true
        let slow = Task {
            try await Task.sleep(for: .milliseconds(150))
            isBusy = true
        }
        Task {
            let result = await debugger.perform(command)
            slow.cancel()
            snapshot = result
            if !isScrubbing { scrub = Double(result.step) }
            if isBusy { isBusy = false }
            isRunning = false
        }
    }
}

/// The panes a narrow screen switches between.
enum DebugPane: String, CaseIterable, Identifiable {
    case term, variables, stack, log
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .term: LocalizedStringResource("Term", bundle: #bundle)
        case .variables: LocalizedStringResource("Variables", bundle: #bundle)
        case .stack: LocalizedStringResource("Stack", bundle: #bundle)
        case .log: LocalizedStringResource("Log", bundle: #bundle)
        }
    }
}

extension DebugTarget: Identifiable {
    public var id: String {
        switch self {
        case .focus: "focus"
        case .variable(let index): "variable-\(index)"
        }
    }
}

extension View {
    /// Presents the debugger for `item`: full screen on iPhone and iPad, so a
    /// wide screen gets its side-by-side panes; a sheet elsewhere.
    func scriptDebugger(item: Binding<DebugRequest?>, document: TxWorkshopDocument) -> some View {
        #if os(iOS)
        fullScreenCover(item: item) { request in
            ScriptDebuggerSheet(document: document, request: request)
        }
        #else
        sheet(item: item) { request in
            ScriptDebuggerSheet(document: document, request: request)
        }
        #endif
    }
}
