import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("What if")
struct WhatIfTests {
    @Test("The order's redeemer and datum are offered for editing")
    func values() throws {
        let values = try WhatIf().values(of: try TransactionInspectionTests.bytes("conway-tx"))
        #expect(values.contains { if case .redeemer(0, "mint", 0) = $0.kind { true } else { false } })
        #expect(values.contains { if case .datum = $0.kind { true } else { false } })
    }

    @Test("No edits changes nothing; a different redeemer changes the run")
    func compare() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let snapshot = try TransactionValidationTests.snapshot()
        let same = try await WhatIf().compare(bytes, edits: [:], snapshot: snapshot, network: .preprod)
        #expect(same.count == 1)
        #expect(same[0].delta == .init(memory: 0, steps: 0))

        // Constr 7 [] instead of what the minting policy expects.
        let changed = try await WhatIf().compare(bytes, edits: ["redeemer-0": "d88080"], snapshot: snapshot, network: .preprod)
        let run = try #require(changed.first)
        #expect(run.before.passed)
        #expect(run.after != nil)
        #expect(run.after != run.before)
    }

    @Test("Bad hex is refused")
    func refused() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        await #expect(throws: WhatIfError.notPlutusData) {
            _ = try await WhatIf().compare(bytes, edits: ["redeemer-0": "zz"], snapshot: try TransactionValidationTests.snapshot(), network: .preprod)
        }
    }
}

@Suite("Script trace")
struct ScriptTraceTests {
    @Test("The order's minting script records a timeline that adds up")
    func timeline() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let snapshot = try TransactionValidationTests.snapshot()
        let trace = try await ScriptTrace.record(bytes, position: 0, snapshot: snapshot, network: .preprod)
        #expect(trace.failure == nil)
        #expect(trace.tag == "mint")
        #expect(trace.stepCount > 1_000)
        // The same budget phase 2 measured.
        let outcome = try await TransactionValidation().validate(bytes, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(trace.consumed == outcome.redeemers.first?.consumed)
        #expect(trace.samples.count <= TimelineObserver.sampleLimit)
        #expect(trace.samples.last?.steps == trace.consumed.steps)
        #expect(zip(trace.samples, trace.samples.dropFirst()).allSatisfy { $0.steps <= $1.steps && $0.step < $1.step })
        #expect(!trace.builtins.isEmpty)
        let calls = trace.events.filter { if case .builtin = $0.kind { true } else { false } }.count
        #expect(calls == trace.builtins.map(\.calls).reduce(0, +))
    }

    @Test("A failing run ends with the machine's error")
    func failing() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let transaction = try WhatIf.apply(["redeemer-0": "d88080"], to: try TransactionValidation.decode(bytes))
        let trace = try await ScriptTrace.record(try transaction.toCBORData(), position: 0, snapshot: try TransactionValidationTests.snapshot(), network: .preprod)
        #expect(trace.failure?.contains("unConstrData") == true)
    }
}
