import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Validation")
struct TransactionValidationTests {
    static func snapshot() throws -> ChainContextSnapshot {
        let url = try #require(Bundle.module.url(forResource: "conway-tx.chain", withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ChainContextSnapshot.self, from: Data(contentsOf: url))
    }

    @Test("Validation field paths lead to their items in the tree")
    func fieldPaths() throws {
        let exploration = CBORExploration(bytes: try TransactionInspectionTests.bytes("conway-tx"))
        let body = try #require(exploration.root?.children?.first)
        let fee = try #require(body.children?.first { $0.name == "fee" })
        #expect(exploration.path(forFieldPath: "transaction_body.fee") == fee.path)
        #expect(exploration.path(forFieldPath: "transaction_body") == [0])
        let address = try #require(exploration.path(forFieldPath: "transaction_body.outputs[1].address"))
        #expect(exploration.item(at: address)?.name == "address")
        // Inputs are a tagged set: the index goes through the tag.
        let input = try #require(exploration.path(forFieldPath: "transaction_body.inputs[1]"))
        #expect(exploration.item(at: input)?.kind == .array)
        #expect(exploration.item(at: input)?.count == 2)
        let redeemer = try #require(exploration.path(forFieldPath: "transaction_witness_set.redeemers[0]"))
        #expect(redeemer.starts(with: [1]))
        // An unknown last step stops at its parent.
        #expect(exploration.path(forFieldPath: "transaction_body.no_such_field") == [0])
        #expect(exploration.path(forFieldPath: "rule.something") == nil)
    }

    @Test("The saved chain data is complete for the fixture")
    func requirements() throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let complete = try TransactionValidation().requirements(for: bytes, snapshot: try Self.snapshot())
        #expect(complete.isComplete)
        #expect(complete.allInputsSpent)
        let none = try TransactionValidation().requirements(for: bytes, snapshot: nil)
        #expect(none.needsProtocolParameters)
        #expect(none.missingInputs.count == 5)
    }

    @Test("As written, the on-chain order passes both phases offline")
    func asWritten() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let outcome = try await TransactionValidation().validate(bytes, snapshot: try Self.snapshot(), network: .preprod, mode: .asWritten)
        #expect(outcome.isValid, "\(outcome.errors.map(\.message))")
        #expect(outcome.redeemers.count == 1)
        let redeemer = try #require(outcome.redeemers.first)
        #expect(redeemer.passed)
        #expect(redeemer.consumed != nil)
        #expect(!redeemer.exceedsDeclared)
        // Preprod's cost models have changed since the order was written.
        #expect(outcome.warnings.contains { $0.kind == "scriptDataHashMismatch" })
    }

    @Test("Now, its inputs are spent and its window has passed")
    func now() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let outcome = try await TransactionValidation().validate(bytes, snapshot: try Self.snapshot(), network: .preprod, mode: .now)
        #expect(!outcome.isValid)
        #expect(outcome.errors.contains { $0.kind == "inputAlreadySpent" && $0.fieldPath == "transaction_body.inputs[0]" })
        #expect(outcome.errors.contains { $0.kind == "scriptDataHashMismatch" })
    }

    @Test("Without protocol parameters, validation says so")
    func noParameters() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        var snapshot = try Self.snapshot()
        snapshot.protocolParameters = nil
        await #expect(throws: ValidationRunError.noProtocolParameters) {
            _ = try await TransactionValidation().validate(bytes, snapshot: snapshot, network: .preprod, mode: .now)
        }
    }
}

@Suite("Validation reports")
struct ValidationReportTests {
    @Test("Markdown and JSON carry the verdict, findings and budgets")
    func reports() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let outcome = try await TransactionValidation().validate(bytes, snapshot: try TransactionValidationTests.snapshot(), network: .preprod, mode: .now)
        let report = ValidationReport(transactionID: "f5cd", network: .preprod, outcome: outcome)
        let markdown = report.markdown()
        #expect(markdown.hasPrefix("# Validation of f5cd\n"))
        #expect(markdown.contains("**Not valid**"))
        #expect(markdown.contains("`inputAlreadySpent` at `transaction_body.inputs[0]`"))
        #expect(markdown.contains("| mint 0 | passed |"))

        let object = try #require(try JSONSerialization.jsonObject(with: report.json()) as? [String: Any])
        #expect(object["isValid"] as? Bool == false)
        let decoded = try JSONDecoder.iso8601.decode(Wrapper.self, from: report.json())
        #expect(decoded.outcome.issues == outcome.issues)
        #expect(decoded.outcome.redeemers == outcome.redeemers)
    }

    @Test("A folder's transaction files are found; a batch table lists each")
    func batch() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tw-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["b.tx", "a.hex", "c.cbor", "notes.txt"] {
            try Data().write(to: folder.appending(path: name))
        }
        #expect(try BatchValidator.transactionFiles(in: folder).map(\.lastPathComponent) == ["a.hex", "b.tx", "c.cbor"])
        let table = BatchValidator.markdown([.init(file: "a.hex", transactionID: nil, outcome: nil, problem: "Not a transaction.")], network: .preprod, mode: .now)
        #expect(table.contains("| a.hex | — | not run: Not a transaction. | 0 | 0 |"))
    }

    struct Wrapper: Decodable { let outcome: ValidationOutcome }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
