import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import SwiftCardanoUPLC
import TxWorkshopCore

/// What to do next in a debugging session.
public enum DebugCommand: Sendable, Equatable {
    case step
    case back
    /// Run until the term being computed has returned its value.
    case over
    /// Run until the current frame is left.
    case out
    case toStep(Int)
    /// Run to the next breakpoint, or the end.
    case resume(Set<DebugBreakpoint>)
    case toEnd
    /// Go to the step the run failed at.
    case toFailure
}

/// A place to stop a run.
public enum DebugBreakpoint: Sendable, Hashable {
    case step(Int)
    /// A builtin, by its name (`equalsByteString`).
    case builtin(String)
    /// A trace message containing this text.
    case trace(String)
    case failure
}

/// How the whole run ends, learned when the session opens.
public struct DebugRunEnd: Sendable, Equatable {
    /// The number of steps the run takes.
    public let steps: Int
    /// The machine's error when the run fails.
    public let failure: String?
    public let consumed: RedeemerOutcome.Budget
    /// The builtins the run calls, by name, for breakpoints.
    public let builtins: [String]
    /// The trace messages the run emits, in order, without repeats.
    public let traces: [String]
}

/// A value as a debugger shows it.
public indirect enum DebugValue: Sendable, Equatable {
    /// A constant: its type and its value as text.
    case constant(type: String, text: String)
    /// Plutus data: its shape, and what it is when the debugger knows (the
    /// script context, the redeemer). The full tree comes from ``ScriptDebugger/detail(_:)``.
    case data(String, label: String?)
    /// A function closed over its environment, read back as a term.
    case closure(String)
    /// A delayed term, read back.
    case delayed(String)
    /// A builtin waiting for more arguments.
    case builtin(name: String, arguments: Int, forces: Int)
    /// A constructor value (Plutus V3 `constr`).
    case constr(tag: UInt64, fields: [DebugValue])

    /// One line, for lists.
    public var summary: String {
        switch self {
        case .constant(let type, let text): "\(text) : \(type)"
        case .data(let shape, let label): [label, shape].compactMap { $0 }.joined(separator: " · ")
        case .closure(let term): Self.firstLine(term)
        case .delayed(let term): "delay " + Self.firstLine(term)
        case .builtin(let name, let arguments, let forces):
            "\(name) (\(arguments) argument\(arguments == 1 ? "" : "s")\(forces > 0 ? ", \(forces) forced" : ""))"
        case .constr(let tag, let fields): "constr \(tag) · \(fields.count) field\(fields.count == 1 ? "" : "s")"
        }
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        return line.count > 120 ? String(line.prefix(120)) + "…" : line
    }
}

/// What ``ScriptDebugger/detail(_:)`` can show in full.
public enum DebugTarget: Sendable, Hashable {
    /// The value being returned, or the term being computed.
    case focus
    /// The variable `#index`.
    case variable(Int)
}

/// A value in full: data as a tree (labelled by a blueprint when one knows
/// it), anything else as text.
public enum DebugDetail: Sendable, Equatable {
    case tree(DataNode, label: String?)
    case text(String)
}

/// A variable in scope: the most recent binding is `#1`.
public struct DebugVariable: Sendable, Equatable, Identifiable {
    public let index: Int
    public let value: DebugValue
    public var id: Int { index }
    public var name: String { "#\(index)" }
}

/// A frame of work still to do.
public struct DebugFrame: Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let detail: String?
}

/// Where a session stands: everything a debugger shows at one step.
public struct DebugSnapshot: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Computing `term`.
        case computing(term: String)
        /// Returning `value` to the innermost frame.
        case returning(DebugValue)
        case finished(result: String)
        case failed(String)
    }

    public let step: Int
    public let phase: Phase
    /// Innermost first.
    public let variables: [DebugVariable]
    /// Innermost first.
    public let frames: [DebugFrame]
    public let consumed: RedeemerOutcome.Budget
    public let logs: [String]
    /// What the last step did: builtins it charged, traces, the end.
    public let events: [String]
    /// The breakpoint the last command stopped at.
    public let stoppedAt: DebugBreakpoint?
}

/// A redeemer's script run, stepped for a debugger. The script is prepared as
/// phase-two validation prepares it, with its real datum, redeemer and
/// context; stepping runs on a large stack, off the caller's actor.
public actor ScriptDebugger {
    /// The longest a single command runs, so a script with no budget (an
    /// approximate cost model) cannot hang the debugger.
    public static let stepLimit = 5_000_000
    /// The longest text a term is shown as.
    public static let termLimit = 6_000

    public nonisolated let end: DebugRunEnd
    /// The redeemer the script runs with, as CBOR hex: to edit and run again.
    public nonisolated let redeemerHex: String
    /// The redeemer read through its blueprint, when one knows the script.
    public nonisolated let redeemerForm: BlueprintForm?
    private var session: CEKSession
    private let labels: Labels

    /// Data the debugger names when it sees it: the script's arguments, with
    /// their full trees. A cheap fingerprint is compared first, so most data
    /// is never compared in full.
    struct Labels: Sendable {
        struct Known: Sendable {
            let fingerprint: String
            let data: PlutusData
            let label: String
            let tree: DataNode
        }

        var known: [Known] = []

        mutating func add(_ data: PlutusData, label: String, tree: DataNode? = nil) {
            known.append(Known(fingerprint: Self.fingerprint(data), data: data, label: label, tree: tree ?? DataNode.plutus(data)))
        }

        func known(_ data: PlutusData) -> Known? {
            let print = Self.fingerprint(data)
            return known.first { $0.fingerprint == print && $0.data == data }
        }

        static func fingerprint(_ data: PlutusData) -> String {
            switch data {
            case .constructor(let constr): ([DataNode.shape(data)] + constr.fields.prefix(3).map(DataNode.shape)).joined(separator: "|")
            case .array(let items): ([DataNode.shape(data)] + items.prefix(3).map(DataNode.shape)).joined(separator: "|")
            default: DataNode.shape(data)
            }
        }
    }

    init(session: CEKSession, end: DebugRunEnd, labels: Labels, redeemerHex: String, redeemerForm: BlueprintForm?) {
        self.session = session
        self.end = end
        self.labels = labels
        self.redeemerHex = redeemerHex
        self.redeemerForm = redeemerForm
    }

    /// A session for the redeemer at `position` in `bytes`, at its first step.
    /// `blueprints` label the redeemer and datum when they know the script.
    /// `redeemer` (CBOR hex) runs the script with a different redeemer, as a
    /// what-if; the transaction itself is not changed.
    public static func open(
        _ bytes: Data, position: Int, snapshot: ChainContextSnapshot, network: CardanoNetwork?,
        blueprints: [StoredBlueprint] = [], applied: [String: BlueprintParameters] = [:], redeemer override: String? = nil
    ) async throws -> ScriptDebugger {
        var transaction = try TransactionValidation.decode(bytes)
        if let override {
            transaction = try WhatIf.apply(["redeemer-\(position)": override], to: transaction)
        }
        guard let parameters = TransactionValidation.protocolParameters(snapshot) else { throw ValidationRunError.noProtocolParameters }
        let redeemers = PhaseTwo.redeemers(of: transaction)
        guard redeemers.indices.contains(position) else { throw ScriptTraceError.noSuchRedeemer(position) }
        let phaseTwo = try PhaseTwo(protocolParameters: parameters, slotTimeline: PhaseTwoRun.timeline(network))
        let prepared = try phaseTwo.prepareScript(
            for: redeemers[position], transaction: transaction, resolvedInputs: TransactionValidation.utxos(snapshot)
        )
        let labels = await Self.labels(prepared, bytes: bytes, position: position, network: network, blueprints: blueprints, applied: applied)
        let redeemerHex = (try? prepared.redeemer.data.toCBORData().hex) ?? ""
        let redeemerForm = await Self.redeemerForm(
            prepared.redeemer.data, bytes: bytes, position: position, network: network, blueprints: blueprints, applied: applied
        )
        let budget: ExBudget = prepared.budgetMeasured ? .restricted : .unlimited

        return await DeepStack.run {
            // Run once to the end to learn how the run ends.
            var probe = CEKSession(prepared.applied, budget: budget, costModel: prepared.costModel)
            var builtins: Set<String> = []
            var traces: [String] = []
            probe.run(limit: ScriptDebugger.stepLimit) { session in
                for event in session.lastEvents {
                    switch event {
                    case .builtin(let function, _): builtins.insert("\(function)")
                    case .log(let message) where !traces.contains(message): traces.append(message)
                    default: break
                    }
                }
                return false
            }
            var failure: String?
            if case .failed(let error) = probe.phase { failure = "\(error)" }
            let consumed = probe.consumedBudget
            let end = DebugRunEnd(
                steps: probe.stepIndex, failure: failure,
                consumed: RedeemerOutcome.Budget(memory: consumed.mem, steps: consumed.cpu),
                builtins: builtins.sorted(), traces: traces
            )
            return ScriptDebugger(
                session: CEKSession(prepared.applied, budget: budget, costModel: prepared.costModel), end: end, labels: labels,
                redeemerHex: redeemerHex, redeemerForm: redeemerForm
            )
        }
    }

    /// Where the session stands now.
    public func snapshot() async -> DebugSnapshot {
        let session = session
        let labels = labels
        return await DeepStack.run { Self.snapshot(session, labels: labels, stoppedAt: nil) }
    }

    /// Does `command` and returns where the session then stands.
    public func perform(_ command: DebugCommand) async -> DebugSnapshot {
        let start = session
        let labels = labels
        let end = end
        let (moved, snapshot) = await DeepStack.run { () -> (CEKSession, DebugSnapshot) in
            var session = start
            var stoppedAt: DebugBreakpoint?
            switch command {
            case .step: session.step()
            case .back: session.stepBack()
            case .over: session.stepOver()
            case .out: session.stepOut()
            case .toStep(let target): session.seek(to: min(target, end.steps))
            case .toEnd: session.seek(to: end.steps)
            case .toFailure:
                if end.failure != nil { session.seek(to: max(0, end.steps - 1)) } else { session.seek(to: end.steps) }
            case .resume(let breakpoints):
                let machineBreakpoints = Set(breakpoints.compactMap(Self.machineBreakpoint))
                if let hit = session.run(to: machineBreakpoints, limit: ScriptDebugger.stepLimit) {
                    stoppedAt = breakpoints.first { Self.machineBreakpoint($0) == hit }
                }
            }
            return (session, Self.snapshot(session, labels: labels, stoppedAt: stoppedAt))
        }
        self.session = moved
        return snapshot
    }

    /// `target` in full: a closure read back with what it closes over, data as
    /// its whole tree.
    public func detail(_ target: DebugTarget) async -> DebugDetail? {
        let session = session
        let labels = labels
        return await DeepStack.run { () -> DebugDetail? in
            let value: SwiftCardanoUPLC.Value
            switch (target, session.phase) {
            case (.focus, .returning(let returned)): value = returned
            case (.focus, .computing(let term, _)): return .text(Self.termText(term))
            case (.focus, .finished(let term)): return .text(Self.termText(term))
            case (.variable(let index), .computing(_, let env)):
                let values = env.values
                guard index >= 1, index <= values.count else { return nil }
                value = values[values.count - index]
            default:
                return nil
            }
            if case .con(.data(let data)) = value {
                if let known = labels.known(data) { return .tree(known.tree, label: known.label) }
                return .tree(DataNode.plutus(data), label: nil)
            }
            if let term = session.term(of: value) { return .text(Self.termText(term)) }
            return .text(Self.value(value, in: session, labels: labels).summary)
        }
    }

    // MARK: - Building snapshots

    static func machineBreakpoint(_ breakpoint: DebugBreakpoint) -> CEKSession.Breakpoint? {
        switch breakpoint {
        case .step(let step): .step(step)
        case .trace(let text): .trace(text)
        case .failure: .failure
        case .builtin(let name): DefaultFunction.allCases.first { "\($0)" == name }.map { .builtin($0) }
        }
    }

    static func snapshot(_ session: CEKSession, labels: Labels, stoppedAt: DebugBreakpoint?) -> DebugSnapshot {
        let phase: DebugSnapshot.Phase
        var environment: Environment?
        switch session.phase {
        case .computing(let term, let env):
            phase = .computing(term: termText(term))
            environment = env
        case .returning(let value):
            phase = .returning(Self.value(value, in: session, labels: labels))
        case .finished(let term):
            phase = .finished(result: termText(term))
        case .failed(let error):
            phase = .failed("\(error)")
        }
        let bindings = environment?.values ?? []
        let variables = bindings.reversed().enumerated().map { offset, bound in
            DebugVariable(index: offset + 1, value: Self.value(bound, in: session, labels: labels))
        }
        let frames = session.context.frames.enumerated().map { index, frame in
            Self.frame(frame, id: index, in: session, labels: labels)
        }
        let consumed = session.consumedBudget
        return DebugSnapshot(
            step: session.stepIndex, phase: phase, variables: variables, frames: frames,
            consumed: RedeemerOutcome.Budget(memory: consumed.mem, steps: consumed.cpu),
            logs: session.logs, events: session.lastEvents.compactMap(describe), stoppedAt: stoppedAt
        )
    }

    static func value(_ value: SwiftCardanoUPLC.Value, in session: CEKSession, labels: Labels) -> DebugValue {
        switch value {
        case .con(.data(let data)):
            if let known = labels.known(data) { return .data(known.tree.summary, label: known.label) }
            return .data(DataNode.shape(data), label: nil)
        case .con(let constant):
            let printer = PrettyPrinter()
            return .constant(type: typeName(constant, printer), text: limited(printer.printConstantValue(constant)))
        case .lambda(let name, let body, _):
            return .closure(BoundedTermPrinter.text(.lambda(parameterName: name, body: body), limit: 160, multiline: false))
        case .delay(let body, _):
            return .delayed(BoundedTermPrinter.text(body, limit: 160, multiline: false))
        case .partiallyApplied(let function, let arguments, let forces):
            return .builtin(name: "\(function)", arguments: arguments.count, forces: forces)
        case .constr(let tag, let fields):
            return .constr(tag: tag, fields: fields.map { Self.value($0, in: session, labels: labels) })
        }
    }

    static func typeName(_ constant: UPLCConstant, _ printer: PrettyPrinter) -> String {
        switch constant {
        case .integer: "integer"
        case .byteString: "bytestring"
        case .string: "string"
        case .unit: "unit"
        case .bool: "bool"
        case .list(let type, _): "list (\(printer.printType(type)))"
        case .pair(let first, let second, _, _): "pair (\(printer.printType(first))) (\(printer.printType(second)))"
        case .data: "data"
        default: "constant"
        }
    }

    static func frame(_ frame: Context, id: Int, in session: CEKSession, labels: Labels) -> DebugFrame {
        func summary(_ value: SwiftCardanoUPLC.Value) -> String { Self.value(value, in: session, labels: labels).summary }
        switch frame {
        case .frameAwaitArg(let function, _):
            return DebugFrame(id: id, title: "Apply: computing the argument", detail: "for " + summary(function))
        case .frameAwaitFunTerm(_, let argument, _):
            // The script's own arguments are named.
            if case .constant(.data(let data)) = argument, let known = labels.known(data) {
                return DebugFrame(id: id, title: "Apply: computing the function", detail: "then the argument: " + known.label)
            }
            return DebugFrame(id: id, title: "Apply: computing the function", detail: "then the argument " + oneLine(argument))
        case .frameAwaitFunValue(let argument, _):
            return DebugFrame(id: id, title: "Apply: computing the function", detail: "to apply to " + summary(argument))
        case .frameForce:
            return DebugFrame(id: id, title: "Force the result", detail: nil)
        case .frameConstr(_, let tag, let remaining, let done, _):
            return DebugFrame(id: id, title: "Build constr \(tag)", detail: "\(done.count + 1) of \(done.count + 1 + remaining.count) fields")
        case .frameCases(_, let branches, _):
            return DebugFrame(id: id, title: "Case", detail: "\(branches.count) branches")
        case .frameCaseApplyFields(let fields, _):
            return DebugFrame(id: id, title: "Case: apply the branch to its fields", detail: "\(fields.count) to go")
        case .noFrame:
            return DebugFrame(id: id, title: "Done", detail: nil)
        }
    }

    static func describe(_ event: CEKEvent) -> String? {
        switch event {
        case .builtin(let function, let cost): "\(function): \(cost.cpu) steps, \(cost.mem) memory"
        case .log(let message): "trace: \(message)"
        case .finished: "finished"
        case .failed(let error): "failed: \(error)"
        case .compute, .returning: nil
        }
    }

    static func termText(_ term: Term<NamedDeBruijn>) -> String {
        BoundedTermPrinter.text(term, limit: termLimit, multiline: true)
    }

    static func oneLine(_ term: Term<NamedDeBruijn>) -> String {
        BoundedTermPrinter.text(term, limit: 120, multiline: false)
    }

    static func limited(_ text: String) -> String {
        text.count > termLimit ? String(text.prefix(termLimit)) + "\n…" : text
    }

    // MARK: - Naming the script's arguments

    /// The redeemer as a blueprint form, when a blueprint knows its script and
    /// the data fits the redeemer's type.
    static func redeemerForm(
        _ data: PlutusData, bytes: Data, position: Int, network: CardanoNetwork?,
        blueprints: [StoredBlueprint], applied: [String: BlueprintParameters]
    ) async -> BlueprintForm? {
        guard !blueprints.isEmpty, let inspection = try? await TransactionInspector().inspection(of: bytes, network: network),
            let view = inspection.redeemers.first(where: { $0.view.position == position })?.view,
            let scriptHash = inspection.redeemerScriptHash(view)
        else { return nil }
        let choices = BlueprintCatalog.choices(
            blueprints, scriptHash: scriptHash, role: .redeemer, purpose: TransactionInspection.purpose(of: view.tag), applied: applied
        )
        for choice in choices {
            guard let schema = choice.validator.redeemer?.schema,
                let value = try? choice.blueprint.decode(data, as: schema, path: "redeemer")
            else { continue }
            return BlueprintForm(blueprint: choice.stored.id, validator: choice.validator.title, value: value)
        }
        return nil
    }

    /// The data the script was applied to, named: the context last, the
    /// redeemer before it, a datum before that. The redeemer and datum are
    /// read through a blueprint when one knows the script.
    static func labels(
        _ prepared: PreparedScript, bytes: Data, position: Int, network: CardanoNetwork?,
        blueprints: [StoredBlueprint], applied: [String: BlueprintParameters]
    ) async -> Labels {
        var arguments: [PlutusData] = []
        var term = prepared.applied.term
        while case .apply(let function, .constant(.data(let data))) = term {
            arguments.insert(data, at: 0)
            term = function
        }
        var labels = Labels()
        guard let context = arguments.last else { return labels }
        // A V2 or V3 context reads by field name when it fits the ledger's type.
        var contextTree: DataNode?
        let version: Int? = switch prepared.version {
        case .v2: 2
        case .v3: 3
        default: nil
        }
        if let version, let schema = ScriptContextSchema.schema(version: version), let blueprint = ScriptContextSchema.blueprint,
            (try? blueprint.decode(context, as: schema, path: "context")) != nil {
            var tree = blueprint.dataNode(context, as: schema)
            tree.validator = nil
            contextTree = tree
        }
        labels.add(context, label: "Script context", tree: contextTree)
        let redeemer = arguments.count >= 2 ? arguments[arguments.count - 2] : nil
        let datum = arguments.count >= 3 ? arguments[arguments.count - 3] : nil

        var scriptHash: String?
        var purpose: String?
        if !blueprints.isEmpty, let inspection = try? await TransactionInspector().inspection(of: bytes, network: network),
            let view = inspection.redeemers.first(where: { $0.view.position == position })?.view {
            scriptHash = inspection.redeemerScriptHash(view)
            purpose = TransactionInspection.purpose(of: view.tag)
        }
        let labeller = BlueprintLabeller(blueprints: blueprints, applied: applied)
        if let redeemer {
            let hex = (try? redeemer.toCBORData().hex) ?? ""
            let tree = labeller.redeemer(hex, scriptHash: scriptHash, purpose: purpose)
            labels.add(redeemer, label: "Redeemer", tree: tree)
        }
        if let datum {
            let tree = labeller.datum((try? datum.toCBORData().hex) ?? "", scriptHash: scriptHash)
            labels.add(datum, label: "Datum", tree: tree)
        }
        return labels
    }
}
