import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import SwiftCardanoUPLC
import TxWorkshopCore

/// One script's run as a timeline: the budget as it was spent, every builtin
/// call and trace message in order, and where it ended.
public struct ScriptTrace: Sendable, Equatable {
    public let tag: String
    public let index: Int
    /// Machine steps taken.
    public let stepCount: Int
    /// The budget spent by each sampled step, for charting.
    public let samples: [Sample]
    /// Builtin calls and trace messages, in order, up to ``eventLimit``.
    public let events: [Event]
    /// Whether events after ``eventLimit`` were left out.
    public let eventsTruncated: Bool
    /// Calls and total cost for each builtin, most costly first.
    public let builtins: [BuiltinUse]
    /// How it ended: `nil` when it succeeded, else the machine's error.
    public let failure: String?
    public let consumed: RedeemerOutcome.Budget

    public static let eventLimit = 20_000

    public struct Sample: Sendable, Equatable {
        public let step: Int
        public let memory: Int64
        public let steps: Int64
    }

    public struct Event: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable {
            case builtin(name: String, memory: Int64, steps: Int64)
            case log(String)
        }

        public let id: Int
        public let step: Int
        public let kind: Kind
        /// The budget spent up to and including it.
        public let consumed: RedeemerOutcome.Budget
    }

    public struct BuiltinUse: Sendable, Equatable, Identifiable {
        public let name: String
        public let calls: Int
        public let memory: Int64
        public let steps: Int64
        public var id: String { name }
    }

    /// Runs the script of the redeemer at `position`, recording its timeline.
    @concurrent
    public static func record(
        _ bytes: Data, position: Int, snapshot: ChainContextSnapshot, network: CardanoNetwork?
    ) async throws -> ScriptTrace {
        let transaction = try TransactionValidation.decode(bytes)
        guard let parameters = TransactionValidation.protocolParameters(snapshot) else { throw ValidationRunError.noProtocolParameters }
        let redeemers = PhaseTwo.redeemers(of: transaction)
        guard redeemers.indices.contains(position) else { throw ScriptTraceError.noSuchRedeemer(position) }
        let view = try TxValidator().inspect(transaction: transaction)
        let described = view.redeemers.first { $0.position == position }
        let phaseTwo = try PhaseTwo(protocolParameters: parameters, slotTimeline: PhaseTwoRun.timeline(network))
        let prepared = try phaseTwo.prepareScript(
            for: redeemers[position], transaction: transaction, resolvedInputs: TransactionValidation.utxos(snapshot)
        )
        // Deep scripts recurse in the machine; run on a deep stack.
        return await DeepStack.run {
            var machine = prepared.machine()
            var observer = TimelineObserver()
            var failure: String?
            do {
                _ = try machine.run(prepared.applied, observer: &observer)
            } catch {
                failure = "\(error)"
            }
            let consumed = machine.consumedBudget
            return ScriptTrace(
                tag: described?.tag ?? "redeemer", index: described?.index ?? position,
                stepCount: observer.stepCount, samples: observer.finishedSamples(),
                events: observer.events, eventsTruncated: observer.eventsTruncated,
                builtins: observer.builtinUses(), failure: failure,
                consumed: .init(memory: consumed.mem, steps: consumed.cpu)
            )
        }
    }
}

public enum ScriptTraceError: Error, Sendable, Equatable, CustomStringConvertible {
    case noSuchRedeemer(Int)

    public var description: String {
        switch self {
        case .noSuchRedeemer(let position): "The transaction has no redeemer at position \(position)."
        }
    }
}

/// Keeps what a timeline needs as the machine runs, without keeping every
/// step: a budget sample every few steps, builtin calls and traces up to a
/// limit, and a running total per builtin.
struct TimelineObserver: CEKObserver {
    private(set) var stepCount = 0
    private var samples: [ScriptTrace.Sample] = []
    private(set) var events: [ScriptTrace.Event] = []
    private(set) var eventsTruncated = false
    private var uses: [String: (calls: Int, memory: Int64, steps: Int64)] = [:]
    private var last: ScriptTrace.Sample?
    /// Sample one step in this many; doubles when the samples fill up.
    private var stride = 64
    static let sampleLimit = 2_000

    mutating func observe(_ step: CEKStep) {
        let consumed = RedeemerOutcome.Budget(memory: step.consumed.mem, steps: step.consumed.cpu)
        let sample = ScriptTrace.Sample(step: step.index, memory: step.consumed.mem, steps: step.consumed.cpu)
        last = sample
        switch step.event {
        case .compute, .returning:
            stepCount = max(stepCount, step.index + 1)
            if step.index.isMultiple(of: stride) { addSample(sample) }
        case .builtin(let function, let cost):
            let name = "\(function)"
            var use = uses[name] ?? (0, 0, 0)
            use.calls += 1
            use.memory += cost.mem
            use.steps += cost.cpu
            uses[name] = use
            addEvent(.init(id: events.count, step: step.index, kind: .builtin(name: name, memory: cost.mem, steps: cost.cpu), consumed: consumed))
        case .log(let message):
            addEvent(.init(id: events.count, step: step.index, kind: .log(message), consumed: consumed))
        case .finished, .failed:
            addSample(sample)
        }
    }

    private mutating func addEvent(_ event: ScriptTrace.Event) {
        guard events.count < ScriptTrace.eventLimit else {
            eventsTruncated = true
            return
        }
        events.append(event)
    }

    private mutating func addSample(_ sample: ScriptTrace.Sample) {
        if samples.last?.step == sample.step { return }
        samples.append(sample)
        if samples.count >= Self.sampleLimit {
            // Keep every other sample and sample half as often from here.
            samples = samples.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
            stride *= 2
        }
    }

    func finishedSamples() -> [ScriptTrace.Sample] {
        guard let last, samples.last?.step != last.step else { return samples }
        return samples + [last]
    }

    func builtinUses() -> [ScriptTrace.BuiltinUse] {
        uses.map { .init(name: $0.key, calls: $0.value.calls, memory: $0.value.memory, steps: $0.value.steps) }
            .sorted { ($0.steps, $0.name) > ($1.steps, $1.name) }
    }
}
