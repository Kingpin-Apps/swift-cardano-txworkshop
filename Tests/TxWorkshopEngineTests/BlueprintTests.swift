import Foundation
import SwiftCardanoCore
import TxWorkshopCore
import Testing

@testable import TxWorkshopEngine

/// Reading a CIP-57 blueprint and filling in its types. The fixture is a real
/// Aiken build (`Fixtures/blueprint/market.ak`, Aiken 1.1.19, stdlib 2.2.0);
/// the expected CBOR is what Aiken's own `cbor.serialise` wrote for the same
/// values (`Fixtures/blueprint/golden.ak`).
@Suite("Blueprints")
struct BlueprintTests {
    typealias Entry = BlueprintValue.Entry

    static let goldenOrder = "d8799f581c00112233445566778899aabbccddeeff00112233445566778899aabb1a004c4b40d8799f1b0000018bcfe56800ffd87a809f42686940ffa241aa0141bb219fc24901000000000000000041ffffd8799fd8799f581caabbccddeeff00112233445566778899aabbccddeeff001122334455ffd8799fd8799fd87a9f581c0102030405060708090a0b0c0d0e0f101112131415161718191a1b1cffffffffd87a9fd8799f01ffd87a9fd8799f21ffd8799f03ffffff182aff"
    static let goldenAction = "d87b9f07d87a80ff"
    static let goldenLongBytes = "5f5840000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f4440414243ff"

    static let order: BlueprintValue = .constructor(index: 0, fields: [
        .bytes("00112233445566778899aabbccddeeff00112233445566778899aabb"),
        .integer("5_000_000"),
        .constructor(index: 0, fields: [.integer("1700000000000")]),
        .constructor(index: 1, fields: []),
        .list([.bytes("6869"), .bytes("")]),
        .map([Entry(key: .bytes("aa"), value: .integer("1")), Entry(key: .bytes("bb"), value: .integer("-2"))]),
        .list([.integer("18446744073709551616"), .bytes("ff")]),
        .constructor(index: 0, fields: [
            .constructor(index: 0, fields: [.bytes("aabbccddeeff00112233445566778899aabbccddeeff001122334455")]),
            .constructor(index: 0, fields: [
                .constructor(index: 0, fields: [.constructor(index: 1, fields: [.bytes("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c")])]),
            ]),
        ]),
        .constructor(index: 1, fields: [
            .constructor(index: 0, fields: [.integer("1")]),
            .constructor(index: 1, fields: [.constructor(index: 0, fields: [.integer("-2")]), .constructor(index: 0, fields: [.integer("3")])]),
        ]),
        .data("42"),
    ])

    func blueprint() throws -> Blueprint {
        let url = try #require(Bundle.module.url(forResource: "market.plutus", withExtension: "json", subdirectory: "Fixtures/blueprint"))
        return try Blueprint(json: Data(contentsOf: url))
    }

    func spend() throws -> Blueprint.Validator {
        try #require(try blueprint().validators.first { $0.title == "market.market.spend" })
    }

    @Test("The preamble, validators and their arguments are read")
    func reads() throws {
        let blueprint = try blueprint()
        #expect(blueprint.preamble.title == "kingpin/bpfix")
        #expect(blueprint.preamble.plutusVersion == 3)
        #expect(blueprint.preamble.compiler?.hasPrefix("Aiken v1.1.19") == true)
        #expect(blueprint.validators.count == 11)

        let spend = try spend()
        #expect(spend.purpose == "spend")
        #expect(blueprint.typeName(try #require(spend.datum).schema) == "Order")
        #expect(Blueprint.genericName("List$ByteArray") == "List<ByteArray>")
        #expect(Blueprint.genericName("Option$cardano/address/StakeCredential") == "Option<StakeCredential>")
        #expect(Blueprint.genericName("Pairs$ByteArray_Int") == "Pairs<ByteArray, Int>")
        let order = try blueprint.resolve(try #require(spend.datum).schema)
        guard case .anyOf(let variants) = order.kind, case .constructor(0, let fields) = variants.first?.kind else {
            Issue.record("Order is not a one-constructor sum: \(order.kind)")
            return
        }
        #expect(fields.map(\.title) == ["owner", "price", "deadline", "partial", "tags", "splits", "pair", "payout", "tree", "extra"])

        let mint = try #require(blueprint.validators.first { $0.title == "market.token.mint" })
        #expect(mint.parameters.map(\.title) == ["owner", "nonce"])
        #expect(blueprint.validators(forScriptHash: spend.hash ?? "").map(\.purpose) == ["spend", "else"])
    }

    @Test("Every validator's script hash agrees with its compiled code")
    func hashes() throws {
        for validator in try blueprint().validators {
            #expect(try validator.computedHash() == validator.hash, "\(validator.title)")
        }
    }

    @Test("A datum encodes byte for byte as Aiken writes it, and decodes back")
    func order() throws {
        let blueprint = try blueprint()
        let schema = try #require(try spend().datum).schema
        #expect(try blueprint.cborHex(Self.order, as: schema, path: "datum") == Self.goldenOrder)

        let decoded = try blueprint.decode(cborHex: Self.goldenOrder, as: schema, path: "datum")
        #expect(try blueprint.cborHex(decoded, as: schema, path: "datum") == Self.goldenOrder)
        guard case .constructor(0, let fields) = decoded else {
            Issue.record("\(decoded)")
            return
        }
        #expect(fields[1] == .integer("5000000"))
        #expect(fields[6] == .list([.integer("18446744073709551616"), .bytes("ff")]))
        #expect(fields[9] == .data("182a"))
    }

    @Test("A redeemer and long bytes encode as Aiken writes them")
    func redeemerAndBytes() throws {
        let blueprint = try blueprint()
        let redeemer = try #require(try spend().redeemer).schema
        let update = BlueprintValue.constructor(index: 2, fields: [.integer("7"), .constructor(index: 1, fields: [])])
        #expect(try blueprint.cborHex(update, as: redeemer, path: "redeemer") == Self.goldenAction)
        #expect(try blueprint.decode(cborHex: Self.goldenAction, as: redeemer, path: "redeemer") == update)

        let bytes = BlueprintSchema(kind: .bytes(.none))
        let long = BlueprintValue.bytes((0...0x43).map { String(format: "%02x", $0) }.joined())
        #expect(try blueprint.cborHex(long, as: bytes, path: "b") == Self.goldenLongBytes)
        #expect(try blueprint.decode(cborHex: Self.goldenLongBytes, as: bytes, path: "b") == long)
    }

    @Test("Each wrong field is named by its path")
    func problems() throws {
        let blueprint = try blueprint()
        let schema = try #require(try spend().datum).schema
        guard case .constructor(0, var fields) = Self.order else { return }
        fields[1] = .integer("")
        fields[2] = .constructor(index: 0, fields: [.integer("soon")])
        fields[4] = .list([.bytes("6869"), .bytes("zz")])
        fields[5] = .map([Entry(key: .bytes("aa"), value: .integer("1")), Entry(key: .bytes("aa"), value: .integer("2"))])
        fields[9] = .data("")
        let problems = blueprint.problems(.constructor(index: 0, fields: fields), as: schema, path: "datum")
        #expect(Set(problems.map(\.path)) == ["datum.price", "datum.deadline[0]", "datum.tags[1]", "datum.splits[1].key", "datum.extra"])
        #expect(problems.first { $0.path == "datum.price" }?.message == "Enter a whole number.")
        #expect(throws: BlueprintError.self) { try blueprint.encode(.constructor(index: 0, fields: fields), as: schema, path: "datum") }
    }

    @Test("A new value starts empty, on None, False and the end of a recursive type")
    func emptyValue() throws {
        let blueprint = try blueprint()
        guard case .constructor(0, let fields) = blueprint.emptyValue(for: try #require(try spend().datum).schema) else {
            Issue.record("Order did not start as its constructor")
            return
        }
        #expect(fields[1] == .integer(""))
        #expect(fields[2] == .constructor(index: 1, fields: []))  // None
        #expect(fields[3] == .constructor(index: 0, fields: []))  // False
        #expect(fields[4] == .list([]))
        #expect(fields[8] == .constructor(index: 0, fields: [.integer("")]))  // Leaf
        #expect(fields[9] == .data(""))
    }

    @Test("Data of another type is refused where it parts from the type")
    func mismatch() throws {
        let blueprint = try blueprint()
        let schema = try #require(try spend().datum).schema
        #expect {
            try blueprint.decode(cborHex: Self.goldenAction, as: schema, path: "datum")
        } throws: { error in
            String(describing: error).contains("Order has no constructor 2")
        }
    }

    @Test("Limits on numbers, bytes and lists are checked")
    func limits() throws {
        let blueprint = try blueprint()
        let hash = BlueprintSchema(kind: .bytes(BlueprintSchema.BytesLimits(minLength: 28, maxLength: 28)))
        #expect(blueprint.problems(.bytes("abcd"), as: hash, path: "h").first?.message == "28 bytes expected, not 2.")
        let percent = BlueprintSchema(kind: .integer(BlueprintSchema.IntegerLimits(minimum: 0, maximum: 100)))
        #expect(blueprint.problems(.integer("101"), as: percent, path: "p").first?.message == "At most 100.")
        #expect(blueprint.problems(.integer("+42"), as: percent, path: "p").isEmpty)
        #expect(blueprint.problems(.integer("1.5"), as: percent, path: "p").first?.message == "\"1.5\" is not a whole number.")
        let pair = BlueprintSchema(kind: .list(BlueprintSchema(kind: .integer(.none)), BlueprintSchema.ItemLimits(minItems: 2, uniqueItems: true)))
        #expect(blueprint.problems(.list([.integer("1")]), as: pair, path: "l").map(\.message) == ["At least 2 items."])
        #expect(blueprint.problems(.list([.integer("1"), .integer("1")]), as: pair, path: "l").map(\.message) == ["The items must all differ."])
    }

    @Test("What is not a blueprint, or refers to a missing type, is refused")
    func refused() {
        #expect(throws: BlueprintError.self) { try Blueprint(json: Data("[]".utf8)) }
        let missing = ##"{"preamble": {"title": "x"}, "validators": [{"title": "a.b.spend", "redeemer": {"schema": {"$ref": "#/definitions/Nope"}}}]}"##
        #expect(throws: BlueprintError.unknownReference("Nope")) { try Blueprint(json: Data(missing.utf8)) }
    }
}

/// Blueprints kept in a recipe: found from a script or an address, and their
/// forms checked before a build.
@Suite("Blueprint forms in a recipe")
struct BlueprintRecipeTests {
    func stored() throws -> StoredBlueprint {
        let url = try #require(Bundle.module.url(forResource: "market.plutus", withExtension: "json", subdirectory: "Fixtures/blueprint"))
        return StoredBlueprint(json: try String(contentsOf: url, encoding: .utf8))
    }

    func spend(_ stored: StoredBlueprint) throws -> Blueprint.Validator {
        try #require(try BlueprintCatalog.blueprint(stored).validators.first { $0.title == "market.market.spend" })
    }

    @Test("A script, or an address it locks, finds its validator")
    func matching() throws {
        let stored = try stored()
        let spend = try spend(stored)
        let script = ScriptDraft.plutus(version: 3, cborHex: try #require(spend.compiledCode))
        let hash = try #require(BlueprintCatalog.scriptHash(script))
        #expect(hash == spend.hash)
        #expect(BlueprintCatalog.choices([stored], scriptHash: hash, role: .datum).map(\.validator.title) == ["market.market.spend"])
        #expect(BlueprintCatalog.choices([stored], scriptHash: hash, role: .redeemer, purpose: "spend").map(\.validator.title) == ["market.market.spend"])
        #expect(BlueprintCatalog.choices([stored], role: .redeemer, purpose: "mint").map(\.validator.title).contains("market.token.mint"))

        let address = try Address(
            paymentPart: .scriptHash(ScriptHash(payload: try TxDocumentCodec.bytes(fromHex: hash))), network: .testnet
        ).toBech32()
        #expect(BlueprintCatalog.scriptHash(address: address, network: .preprod) == hash)
        #expect(BlueprintCatalog.scriptHash(.native(json: "{}")) == nil)
    }

    @Test("A recipe's forms are checked by field, and a valid one builds from its CBOR")
    func check() throws {
        let stored = try stored()
        let spend = try spend(stored)
        let blueprint = try BlueprintCatalog.blueprint(stored)
        let redeemerSchema = try #require(spend.redeemer).schema
        let good = BlueprintValue.constructor(index: 2, fields: [.integer("7"), .constructor(index: 1, fields: [])])
        let bad = BlueprintValue.constructor(index: 2, fields: [.integer("seven"), .constructor(index: 1, fields: [])])

        func recipe(_ value: BlueprintValue, blueprints: [StoredBlueprint]) throws -> BuildRecipe {
            BuildRecipe(
                changeAddress: "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x",
                scriptInputs: [ScriptInputDraft(
                    input: String(repeating: "ab", count: 32) + "#0",
                    redeemer: (try? blueprint.cborHex(value, as: redeemerSchema, path: "redeemer")) ?? "",
                    redeemerForm: BlueprintForm(blueprint: stored.id, validator: spend.title, value: value)
                )],
                blueprints: blueprints
            )
        }
        let fine = RecipeCheck.problems(try recipe(good, blueprints: [stored]), network: .preprod)
        #expect(!fine.contains { $0.field == "Redeemer" }, "\(fine)")

        let wrong = RecipeCheck.problems(try recipe(bad, blueprints: [stored]), network: .preprod).filter { $0.field == "Redeemer" }
        #expect(wrong.map(\.message) == ["redeemer.price: \"seven\" is not a whole number."])

        let lost = RecipeCheck.problems(try recipe(good, blueprints: []), network: .preprod).filter { $0.field == "Redeemer" }
        #expect(lost.first?.message.contains("no longer in the document") == true)
    }

    @Test("Recipes saved before blueprints still open")
    func oldRecipe() throws {
        let old = #"{"outputs": [{"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF", "address": "x", "assets": [], "datum": {"none": {}}}], "mints": [{"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FE", "script": {"native": {"json": ""}}, "assets": [], "redeemer": ""}]}"#
        let recipe = try JSONDecoder().decode(BuildRecipe.self, from: Data(old.utf8))
        #expect(recipe.blueprints.isEmpty)
        #expect(recipe.outputs.first?.datumForm == nil)
        #expect(recipe.mints.first?.redeemerForm == nil)
        let form = BlueprintForm(blueprint: "b", validator: "v", value: .constructor(index: 0, fields: [.list([.integer("1")]), .map([.init(key: .bytes("aa"), value: .data("42"))])]))
        #expect(try JSONDecoder().decode(BlueprintForm.self, from: JSONEncoder().encode(form)) == form)
    }
}

/// Inspected datums and redeemers read as their validators' blueprint types.
@Suite("Blueprint labels in the inspector")
struct BlueprintLabellingTests {
    func stored() throws -> StoredBlueprint {
        try BlueprintRecipeTests().stored()
    }

    @Test("An output's inline datum at the script's address shows its fields by name")
    func outputDatum() async throws {
        let stored = try stored()
        let spend = try BlueprintRecipeTests().spend(stored)
        let scriptAddress = try Address(
            paymentPart: .scriptHash(ScriptHash(payload: try TxDocumentCodec.bytes(fromHex: try #require(spend.hash)))), network: .testnet
        ).toBech32()
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex],
            outputs: [OutputDraft(address: scriptAddress, lovelace: 5_000_000, datum: .inline(BlueprintTests.goldenOrder))],
            changeAddress: address
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)

        let labelled = inspection.labelled(with: [stored])
        guard case .inline(_, let tree, _)? = labelled.outputs.first(where: { $0.address.text == scriptAddress })?.datum else {
            Issue.record("No inline datum at the script address")
            return
        }
        #expect(tree.validator == "market.market.spend")
        #expect(tree.typeName == "Order")
        #expect(tree.summary == "Order · 10 fields")
        #expect(tree.children?.map(\.label) == ["owner", "price", "deadline", "partial", "tags", "splits", "pair", "payout", "tree", "extra"])
        #expect(tree.children?[2].summary == "Some · 1 field")
        #expect(tree.children?[3].summary == "True")
        #expect(tree.children?[4].summary == "List<ByteArray> · 2")
        #expect(tree.children?[5].summary == "Pairs<ByteArray, Int> · 2")
        #expect(tree.children?[1].value == "5000000")

        // Without the blueprint it is the plain tree, and a key's output is untouched.
        #expect(inspection.labelled(with: []) == inspection)
        guard case .inline(_, let plain, _)? = inspection.outputs.first(where: { $0.address.text == scriptAddress })?.datum else { return }
        #expect(plain.summary == "Constr 0 · 10 fields")
    }

    @Test("A redeemer reads as its type; data of another shape stays plain")
    func redeemer() throws {
        let stored = try stored()
        let spend = try BlueprintRecipeTests().spend(stored)
        let labeller = BlueprintLabeller(blueprints: [stored])
        let tree = try #require(labeller.redeemer(BlueprintTests.goldenAction, scriptHash: spend.hash, purpose: "spend"))
        #expect(tree.summary == "Update · 2 fields")
        #expect(tree.children?.map(\.label) == ["price", "deadline"])
        #expect(tree.children?[1].summary == "None")
        // An Order is not an Action.
        #expect(labeller.redeemer(BlueprintTests.goldenOrder, scriptHash: spend.hash, purpose: "spend") == nil)
        #expect(labeller.redeemer(BlueprintTests.goldenAction, scriptHash: String(repeating: "00", count: 28), purpose: "spend") == nil)
    }
}
