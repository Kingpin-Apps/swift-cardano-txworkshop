import Foundation
import SwiftCardanoCore
import TxWorkshopCore
import Testing

@testable import TxWorkshopEngine

/// A datum written with an indefinite-length map decodes to
/// `PlutusData.indefiniteMap`. The inspector, the blueprint codec and the
/// debugger show it as the map it is.
@Suite("Indefinite maps in data")
struct IndefiniteMapDataTests {
    /// `Constr 0 [Map [(I 1, I 2)]]` with an indefinite-length map.
    static let datum = "d8799fbf0102ffff"

    static let schema = BlueprintSchema(kind: .constructor(index: 0, fields: [
        BlueprintSchema(title: "scores", kind: .map(
            keys: BlueprintSchema(kind: .integer(.none)), values: BlueprintSchema(kind: .integer(.none)), .none
        ))
    ]))

    private func decoded() throws -> PlutusData {
        try PlutusData.fromCBOR(data: Self.datum.hexStringToData)
    }

    private func blueprint() throws -> Blueprint {
        try Blueprint(json: Data(##"{"preamble": {"title": "x"}, "validators": []}"##.utf8))
    }

    @Test("The inspector shows it as a map")
    func inspector() throws {
        let tree = DataNode.plutus(try decoded())
        let map = try #require(tree.children?.first)
        #expect(map.kind == .map)
        #expect(map.summary == "map · 1")
        #expect(map.children?.first?.label == "1")
        #expect(map.children?.first?.value == "2")
    }

    @Test("A blueprint map decodes from it")
    func blueprintDecode() throws {
        let value = try blueprint().decode(cborHex: Self.datum, as: Self.schema, path: "datum")
        #expect(value == .constructor(index: 0, fields: [
            .map([BlueprintValue.Entry(key: .integer("1"), value: .integer("2"))])
        ]))
    }

    @Test("Blueprint labels reach into it")
    func blueprintLabels() throws {
        let tree = try blueprint().dataNode(try decoded(), as: Self.schema)
        let map = try #require(tree.children?.first)
        #expect(map.kind == .map)
        #expect(map.children?.first?.label == "1")
    }

    @Test("The debugger names it a map")
    func debuggerShape() throws {
        guard case .constructor(let constr) = try decoded(), let map = constr.fields.first else {
            Issue.record("not a constructor")
            return
        }
        #expect(DataNode.shape(map) == "map · 1")
        #expect(Blueprint.shape(map) == "a map")
    }
}
