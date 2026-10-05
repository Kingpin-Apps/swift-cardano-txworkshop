import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore
import SwiftCardanoUPLC

@testable import TxWorkshopEngine

/// Stepping through the order's minting script in `conway-tx`, as the app's
/// debugger does.
@Suite("Script debugger")
struct ScriptDebuggerTests {
    func debugger(_ bytes: Data? = nil) async throws -> ScriptDebugger {
        let bytes = try bytes ?? TransactionInspectionTests.bytes("conway-tx")
        return try await ScriptDebugger.open(bytes, position: 0, snapshot: try TransactionValidationTests.snapshot(), network: .preprod)
    }

    @Test("The run ends as phase two measured it")
    func end() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let debugger = try await debugger(bytes)
        let trace = try await ScriptTrace.record(bytes, position: 0, snapshot: try TransactionValidationTests.snapshot(), network: .preprod)
        #expect(debugger.end.failure == nil)
        #expect(debugger.end.consumed == trace.consumed)
        #expect(debugger.end.steps > 1_000)
        #expect(Set(debugger.end.builtins) == Set(trace.builtins.map(\.name)))

        let start = await debugger.snapshot()
        #expect(start.step == 0)
        let finished = await debugger.perform(.toEnd)
        #expect(finished.consumed == trace.consumed)
        guard case .finished = finished.phase else {
            Issue.record("\(finished.phase)")
            return
        }
    }

    @Test("A step back returns to exactly where the step began")
    func back() async throws {
        let debugger = try await debugger()
        var before = await debugger.perform(.toStep(500))
        #expect(before.step == 500)
        for _ in 0..<40 {
            let after = await debugger.perform(.step)
            #expect(after.step == before.step + 1)
            let again = await debugger.perform(.back)
            #expect(again == before)
            before = await debugger.perform(.step)
        }
    }

    @Test("Running to a builtin stops when it is charged, and step over returns at the same depth")
    func breakpointsAndOver() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let trace = try await ScriptTrace.record(bytes, position: 0, snapshot: try TransactionValidationTests.snapshot(), network: .preprod)
        let builtin = try #require(trace.builtins.first?.name)
        let debugger = try await debugger(bytes)
        let stopped = await debugger.perform(.resume([.builtin(builtin)]))
        #expect(stopped.stoppedAt == .builtin(builtin))
        #expect(stopped.events.contains { $0.hasPrefix(builtin + ":") })

        // Over a computation: back at the same depth, with its value.
        var snapshot = await debugger.perform(.toStep(200))
        while case .returning = snapshot.phase { snapshot = await debugger.perform(.step) }
        let depth = snapshot.frames.count
        let over = await debugger.perform(.over)
        guard case .returning = over.phase else {
            Issue.record("Step over ended \(over.phase)")
            return
        }
        #expect(over.frames.count <= depth)
        #expect(over.step > snapshot.step)
    }

    @Test("The script's arguments are named where they appear")
    func labels() async throws {
        let debugger = try await debugger()
        var names: Set<String> = []
        var snapshot = await debugger.snapshot()
        for _ in 0..<400 where !names.contains("Script context") {
            for variable in snapshot.variables {
                if case .data(_, let label?) = variable.value { names.insert(label) }
            }
            snapshot = await debugger.perform(.step)
        }
        #expect(names.contains("Script context"))
        #expect(names.contains("Redeemer"))

        // In full, the context is its whole tree.
        let index = try #require(snapshot.variables.first { if case .data(_, "Script context") = $0.value { true } else { false } }?.index)
        guard case .tree(let tree, let label)? = await debugger.detail(.variable(index)) else {
            Issue.record("No tree for the context")
            return
        }
        #expect(label == "Script context")
        #expect((tree.children?.count ?? 0) > 0)
    }

    @Test("A closure reads back in full, with what it closes over")
    func closure() async throws {
        let debugger = try await debugger()
        var snapshot = await debugger.perform(.toStep(300))
        for _ in 0..<300 where !snapshot.variables.contains(where: { if case .closure = $0.value { true } else { false } }) {
            snapshot = await debugger.perform(.step)
        }
        let index = try #require(snapshot.variables.first { if case .closure = $0.value { true } else { false } }?.index)
        guard case .text(let text)? = await debugger.detail(.variable(index)) else {
            Issue.record("No text for the closure")
            return
        }
        #expect(text.hasPrefix("(lam"))
    }

    @Test("Each step's snapshot is quick, however large the script")
    func speed() async throws {
        let debugger = try await debugger()
        _ = await debugger.perform(.toStep(1_000))
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            for _ in 0..<100 { _ = await debugger.perform(.step) }
        }
        #expect(elapsed < .seconds(2), "100 steps took \(elapsed)")
    }

    @Test("A failing run goes to its failure, and stops at a failure breakpoint")
    func failing() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let transaction = try WhatIf.apply(["redeemer-0": "d88080"], to: try TransactionValidation.decode(bytes))
        let debugger = try await debugger(try transaction.toCBORData())
        let failure = try #require(debugger.end.failure)
        #expect(failure.contains("unConstrData"))

        let before = await debugger.perform(.toFailure)
        #expect(before.step == debugger.end.steps - 1)
        let failed = await debugger.perform(.step)
        #expect(failed.phase == .failed(failure))

        _ = await debugger.perform(.toStep(0))
        let stopped = await debugger.perform(.resume([.failure]))
        #expect(stopped.stoppedAt == .failure)
        #expect(stopped.phase == .failed(failure))
    }
}

@Suite("Bounded term printer")
struct BoundedTermPrinterTests {
    @Test("Lambda chains stay on a line, variables read as #n, and long terms stop at the limit")
    func printing() throws {
        let body = Term<NamedDeBruijn>.apply(
            function: .var(NamedDeBruijn(text: "f", index: DeBruijn(2))), argument: .var(NamedDeBruijn(text: "x", index: DeBruijn(1)))
        )
        let term = Term<NamedDeBruijn>.lambda(parameterName: NamedDeBruijn(text: "f", index: DeBruijn(0)),
            body: .lambda(parameterName: NamedDeBruijn(text: "x", index: DeBruijn(0)), body: body))
        #expect(BoundedTermPrinter.text(term, limit: 200, multiline: true) == "(lam (lam\n  [ #2 #1]))")
        #expect(BoundedTermPrinter.text(term, limit: 200, multiline: false) == "(lam (lam [ #2 #1]))")
        #expect(BoundedTermPrinter.text(term, limit: 8, multiline: false) == "(lam (la …")
    }
}
