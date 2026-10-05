import Charts
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Identifies the redeemer whose script to trace.
struct TraceRequest: Identifiable {
    let position: Int
    var id: Int { position }
}

/// One script's run as a timeline: budget spent over the machine's steps,
/// builtin calls and trace messages in order, and the costliest builtins.
struct ScriptTraceSheet: View {
    let document: TxWorkshopDocument
    let request: TraceRequest
    @Environment(\.dismiss) private var dismiss
    @State private var trace: LoadState<ScriptTrace> = .loading
    @State private var showsLogsOnly = false

    var body: some View {
        NavigationStack {
            Group {
                switch trace {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Text("No trace", bundle: #bundle)
                    } description: {
                        Text(verbatim: message)
                    } actions: {
                        FetchChainDataButton(document: document) {
                            Task { await record() }
                        }
                    }
                case .loaded(let trace):
                    content(trace)
                }
            }
            .navigationTitle(Text("Script Trace", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                }
            }
            .task { await record() }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 720)
        #endif
    }

    private func record() async {
        guard let bytes = document.content.transaction, let snapshot = document.content.chainContext else {
            trace = .failed(String(localized: "Fetch or enter chain data first.", bundle: #bundle))
            return
        }
        trace = .loading
        do {
            trace = .loaded(try await ScriptTrace.record(bytes, position: request.position, snapshot: snapshot, network: document.content.network))
        } catch {
            trace = .failed(String(describing: error))
        }
    }

    private func content(_ trace: ScriptTrace) -> some View {
        List {
            Section {
                Label {
                    if let failure = trace.failure {
                        Text("Failed after \(trace.stepCount) steps: \(failure)", bundle: #bundle)
                    } else {
                        Text("Succeeded in \(trace.stepCount) machine steps.", bundle: #bundle)
                    }
                } icon: {
                    Image(systemName: trace.failure == nil ? "checkmark.circle" : "xmark.circle")
                }
                .labelStyle(.status(trace.failure == nil ? TWColor.success : TWColor.failure))
                BudgetChart(trace: trace)
                    .frame(height: 180)
            } header: {
                Text(verbatim: "\(trace.tag) \(trace.index)")
            }
            Section {
                ForEach(trace.builtins.prefix(8)) { use in
                    HStack {
                        Text(verbatim: use.name)
                            .font(TWFont.bytesSmall)
                        Spacer()
                        Text("\(use.calls, format: .number) calls · \(use.steps, format: .number) steps", bundle: #bundle)
                            .font(TWFont.figure)
                            .foregroundStyle(TWColor.secondaryText)
                    }
                }
            } header: {
                Text("Costliest builtins", bundle: #bundle)
            }
            Section {
                Toggle(isOn: $showsLogsOnly) {
                    Text("Trace messages only", bundle: #bundle)
                }
                ForEach(showsLogsOnly ? trace.events.filter(\.isLog) : trace.events) { event in
                    EventRow(event: event)
                }
                if trace.eventsTruncated {
                    Text("Only the first \(ScriptTrace.eventLimit) events are listed.", bundle: #bundle)
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                }
            } header: {
                Text("Timeline", bundle: #bundle)
            }
        }
    }
}

/// Steps spent over the run, with trace messages marked.
private struct BudgetChart: View {
    let trace: ScriptTrace

    var body: some View {
        Chart {
            ForEach(trace.samples, id: \.step) { sample in
                LineMark(
                    x: .value(String(localized: "Machine step", bundle: #bundle), sample.step),
                    y: .value(String(localized: "Steps spent", bundle: #bundle), sample.steps)
                )
            }
            ForEach(trace.events.filter(\.isLog)) { event in
                RuleMark(x: .value(String(localized: "Machine step", bundle: #bundle), event.step))
                    .foregroundStyle(TWColor.warning.opacity(0.6))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let steps = value.as(Int64.self) {
                        Text(steps, format: .number.notation(.compactName))
                    }
                }
            }
        }
        .chartXAxisLabel {
            Text("Machine step", bundle: #bundle)
        }
        .chartYAxisLabel {
            Text("Steps spent", bundle: #bundle)
        }
        .accessibilityLabel(Text("Budget spent over the run", bundle: #bundle))
        .accessibilityValue(Text("\(trace.consumed.steps) steps and \(trace.consumed.memory) memory in \(trace.stepCount) machine steps", bundle: #bundle))
    }
}

private struct EventRow: View {
    let event: ScriptTrace.Event

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TWSpacing.s) {
            Text(verbatim: String(event.step))
                .font(TWFont.bytesSmall)
                .foregroundStyle(TWColor.secondaryText)
                .frame(minWidth: 60, alignment: .trailing)
            switch event.kind {
            case .builtin(let name, _, let steps):
                Text(verbatim: name)
                    .font(TWFont.bytesSmall)
                Spacer()
                Text("+\(steps, format: .number)", bundle: #bundle)
                    .font(TWFont.figure)
                    .foregroundStyle(TWColor.secondaryText)
            case .log(let message):
                Label {
                    Text(verbatim: message)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "text.bubble")
                }
                .labelStyle(.status(TWColor.warning))
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension ScriptTrace.Event {
    var isLog: Bool {
        if case .log = kind { return true }
        return false
    }
}
