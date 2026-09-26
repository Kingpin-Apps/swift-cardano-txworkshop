import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("CBOR explorer")
struct CBORExplorationTests {
    static func hex(_ text: String) throws -> Data { try TxDocumentCodec.bytes(fromHex: text) }

    @Test("A transaction's fields are named, and bytes lead to their item")
    func transactionNames() throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let exploration = CBORExploration(bytes: bytes)
        #expect(exploration.problem == nil)
        let root = try #require(exploration.root)
        #expect(root.kind == .array && root.count == 4)
        #expect(root.children?.map(\.name) == ["transaction body", "witness set", "is valid", "auxiliary data"])

        let body = try #require(root.children?.first)
        let fee = try #require(body.children?.first { $0.name == "fee" })
        #expect(fee.label == "2")
        #expect(fee.preview == "340252")
        let keyRange = try #require(fee.keyRange)
        // The fee's key and value bytes both lead to the fee.
        #expect(exploration.path(toByte: keyRange.lowerBound) == fee.path)
        #expect(exploration.path(toByte: fee.start) == fee.path)
        #expect(exploration.item(at: fee.path) == fee)

        let outputs = try #require(body.children?.first { $0.name == "outputs" })
        #expect(outputs.children?.first?.name == "output 0")
        #expect(outputs.children?.first?.children?.first?.name == "address")
        #expect(body.children?.contains { $0.name == "collateral return" } == true)
        let witnesses = try #require(root.children?[1])
        #expect(witnesses.children?.map(\.name).contains("vkey witnesses") == true)
        #expect(exploration.diagnostic(at: fee.path) == "340252")
    }

    @Test("Diagnostic notation marks indefinite lengths, float widths and chunks")
    func diagnostic() throws {
        let array = CBORExploration(bytes: try Self.hex("9f018202 03ff".replacingOccurrences(of: " ", with: "")))
        #expect(array.diagnostic(at: []) == "[_ \n  1,\n  [\n    2,\n    3\n  ]\n]")
        #expect(array.root?.flags == [.indefiniteLength])

        let map = CBORExploration(bytes: try Self.hex("a26161fa3f8000002038ff"))
        #expect(map.diagnostic(at: []) == "{\n  \"a\": 1.0_2,\n  -1: -256\n}")
        #expect(map.root?.children?.first?.flags == [.nonPreferredFloat])

        let chunks = CBORExploration(bytes: try Self.hex("5f42010241 03ff".replacingOccurrences(of: " ", with: "")))
        #expect(chunks.diagnostic(at: []) == "(_ h'0102', h'03')")
        #expect(chunks.root?.count == 3)
        #expect(chunks.root?.children?.count == 2)

        let tagged = CBORExploration(bytes: try Self.hex("d9010281f6"))
        #expect(tagged.root?.kind == .tag(258))
        #expect(tagged.diagnostic(at: []) == "258([\n  null\n])")
    }

    @Test("Non-canonical heads and keys are flagged")
    func flags() throws {
        #expect(CBORExploration(bytes: try Self.hex("1805")).root?.flags == [.overlongHead])
        let unsorted = CBORExploration(bytes: try Self.hex("a202000100"))
        #expect(unsorted.root?.flags.contains(.unsortedMapKeys) == true)
    }

    @Test("Truncated bytes give the items read so far, and where decoding stopped")
    func partial() throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let exploration = CBORExploration(bytes: bytes.prefix(120))
        let problem = try #require(exploration.problem)
        #expect(problem.offset != nil)
        let root = try #require(exploration.root)
        #expect(!root.isComplete)
        #expect(root.children?.first?.name == "transaction body")
        #expect(exploration.diagnostic(at: [])?.contains("…") == true)

        let trailing = CBORExploration(bytes: try Self.hex("0102"))
        #expect(trailing.problem?.offset == 1)
        #expect(trailing.root?.isComplete == true)
    }
}

@Suite("CBOR explorer depth")
struct CBORExplorationDepthTests {
    @Test("Data nested 60,000 levels deep explores, prints and is freed")
    func deep() async throws {
        let depth = 60_000
        let bytes = Data(repeating: 0x81, count: depth) + Data([0x00])
        let exploration = await CBORExploration.explore(bytes)
        #expect(exploration.problem == nil)
        let text = try #require(await exploration.diagnosticText(at: [], limit: 100_000_000))
        #expect(text.filter { $0 == "[" }.count == depth)
        // The tree stops at its depth limit.
        var item = exploration.root
        var levels = 0
        while let next = item?.children?.first {
            item = next
            levels += 1
        }
        #expect(levels == CBORItem.maxDepth)
        #expect(item?.childrenOmitted == true)
    }
}

@Suite("Schema check")
struct SchemaCheckTests {
    @Test("The default era is the latest the transaction allows")
    func defaultEra() {
        #expect(SchemaCheck.defaultEra(possibleEras: "babbage…conway") == "conway")
        #expect(SchemaCheck.defaultEra(possibleEras: "shelley…mary") == "mary")
        #expect(SchemaCheck.defaultEra(possibleEras: "") == "conway")
    }

    @Test("A ledger-accepted transaction passes its era's schema")
    func valid() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let report = try await SchemaCheck().checkTransaction(bytes, era: "conway")
        #expect(report.isValid, "\(report.issues)")
        #expect(try SchemaCheck().ruleNames(era: "conway").contains("transaction_body"))
    }

    @Test("A broken fee is reported, linked to the fee")
    func brokenFee() async throws {
        var bytes = try TransactionInspectionTests.bytes("conway-tx")
        let exploration = CBORExploration(bytes: bytes)
        let fee = try #require(exploration.root?.children?.first?.children?.first { $0.name == "fee" })
        // The fee becomes a text string of the same length: 0x64 + "abcd".
        bytes.replaceSubrange(fee.start..<fee.end, with: Data([0x64]) + Data("abcd".utf8))
        let report = try await SchemaCheck().checkTransaction(bytes, era: "conway")
        #expect(!report.isValid)
        #expect(report.issues.contains { $0.itemPath == fee.path }, "\(report.issues)")
    }

    @Test("An item checks against a chosen rule, with issues under its path")
    func chosenRule() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let exploration = CBORExploration(bytes: bytes)
        let body = try #require(exploration.root?.children?.first)
        let asBody = try await SchemaCheck().check(bytes, range: body.range, path: body.path, rule: "transaction_body", era: "conway")
        #expect(asBody.isValid, "\(asBody.issues)")
        let asWitnesses = try await SchemaCheck().check(bytes, range: body.range, path: body.path, rule: "transaction_witness_set", era: "conway")
        #expect(!asWitnesses.isValid)
        #expect(asWitnesses.issues.allSatisfy { $0.itemPath.map { Array($0.prefix(body.path.count)) == body.path } ?? true })
    }
}
