import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Where the run stands, the stepping buttons, the breakpoints and the
/// timeline.
struct DebugControls: View {
    let end: DebugRunEnd
    let snapshot: DebugSnapshot
    let isBusy: Bool
    @Binding var breakpoints: Set<DebugBreakpoint>
    @Binding var scrub: Double
    @Binding var isScrubbing: Bool
    let perform: (DebugCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                status
                Spacer()
                Text("Step \(snapshot.step, format: .number) of \(end.steps, format: .number)", bundle: #bundle)
                    .font(TWFont.figure)
                    .foregroundStyle(TWColor.secondaryText)
                    .accessibilityIdentifier("debugStep")
            }
            HStack(spacing: TWSpacing.m) {
                button("Step Back", systemImage: "arrow.uturn.backward", command: .back, key: .leftArrow, id: "debugBack")
                    .disabled(snapshot.step == 0)
                button("Step", systemImage: "arrow.right", command: .step, key: .rightArrow, id: "debugStep1")
                button("Step Over", systemImage: "arrow.turn.down.right", command: .over, key: .downArrow, id: "debugOver")
                button("Step Out", systemImage: "arrow.turn.left.up", command: .out, key: .upArrow, id: "debugOut")
                button("Continue", systemImage: "play", command: .resume(breakpoints), key: .return, id: "debugContinue")
                Spacer()
                breakpointMenu
                if end.failure != nil {
                    Button {
                        perform(.toFailure)
                    } label: {
                        Label {
                            Text("Go to Failure", bundle: #bundle)
                        } icon: {
                            Image(systemName: "xmark.octagon")
                        }
                    }
                    .accessibilityIdentifier("debugToFailure")
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(isBusy)
            // No `step:`: on macOS it draws a tick mark per step, seconds of
            // work on every update for a run of thousands of steps.
            Slider(value: $scrub, in: 0...Double(max(end.steps, 1))) {
                Text("Timeline", bundle: #bundle)
            } onEditingChanged: { editing in
                isScrubbing = editing
                if !editing { perform(.toStep(Int(scrub.rounded()))) }
            }
            .accessibilityIdentifier("debugTimeline")
            HStack {
                Text("\(snapshot.consumed.steps, format: .number) steps · \(snapshot.consumed.memory, format: .number) memory", bundle: #bundle)
                Spacer()
                Text("of \(end.consumed.steps, format: .number) · \(end.consumed.memory, format: .number)", bundle: #bundle)
            }
            .font(TWFont.figure)
            .foregroundStyle(TWColor.secondaryText)
        }
        .padding(TWSpacing.m)
    }

    @ViewBuilder private var status: some View {
        switch snapshot.phase {
        case .failed(let message):
            TWErrorText(message)
        case .finished:
            Label {
                Text("Finished", bundle: #bundle)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .labelStyle(.status(TWColor.success))
        default:
            if let stoppedAt = snapshot.stoppedAt {
                Label {
                    Text(verbatim: Self.describe(stoppedAt))
                } icon: {
                    Image(systemName: "pause.circle")
                }
                .labelStyle(.status(TWColor.warning))
            } else if let failure = end.failure {
                Text("The run fails: \(failure)", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
                    .lineLimit(2)
            } else {
                Text("The run succeeds.", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
            }
        }
    }

    private func button(
        _ title: LocalizedStringResource, systemImage: String, command: DebugCommand, key: KeyEquivalent, id: String
    ) -> some View {
        Button {
            perform(command)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .twHitTarget()
        }
        .keyboardShortcut(key, modifiers: .command)
        .help(Text(title))
        .accessibilityIdentifier(id)
    }

    /// Stop on failure, on a builtin the run calls, or on a trace message it emits.
    private var breakpointMenu: some View {
        Menu {
            Toggle(isOn: binding(.failure)) {
                Text("On Failure", bundle: #bundle)
            }
            if !end.builtins.isEmpty {
                Menu {
                    ForEach(end.builtins, id: \.self) { name in
                        Toggle(isOn: binding(.builtin(name))) { Text(verbatim: name) }
                    }
                } label: {
                    Text("On a Builtin", bundle: #bundle)
                }
            }
            if !end.traces.isEmpty {
                Menu {
                    ForEach(end.traces.prefix(50), id: \.self) { message in
                        Toggle(isOn: binding(.trace(message))) { Text(verbatim: message) }
                    }
                } label: {
                    Text("On a Trace", bundle: #bundle)
                }
            }
            if breakpoints.count > 1 || !breakpoints.contains(.failure) {
                Button(role: .destructive) {
                    breakpoints = [.failure]
                } label: {
                    Text("Clear Breakpoints", bundle: #bundle)
                }
            }
        } label: {
            Label {
                Text("Breakpoints (\(breakpoints.count))", bundle: #bundle)
            } icon: {
                Image(systemName: breakpoints.isEmpty ? "circle.dashed" : "smallcircle.filled.circle")
            }
            .twHitTarget()
        }
        .accessibilityIdentifier("debugBreakpoints")
    }

    private func binding(_ breakpoint: DebugBreakpoint) -> Binding<Bool> {
        Binding {
            breakpoints.contains(breakpoint)
        } set: { on in
            if on { breakpoints.insert(breakpoint) } else { breakpoints.remove(breakpoint) }
        }
    }

    static func describe(_ breakpoint: DebugBreakpoint) -> String {
        switch breakpoint {
        case .step(let step): String(localized: "Stopped at step \(step)", bundle: #bundle)
        case .builtin(let name): String(localized: "Stopped at \(name)", bundle: #bundle)
        case .trace(let text): String(localized: "Stopped at the trace \(text)", bundle: #bundle)
        case .failure: String(localized: "Stopped at the failure", bundle: #bundle)
        }
    }
}
