import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// A transaction read back into the Build form builds the same transaction
/// again, and the form can then change it.
@Suite("Editing a transaction")
struct RecipeImporterTests {
    /// Builds `recipe`, reads the result back into a form, and builds that.
    static func roundTrip(_ recipe: BuildRecipe) async throws -> (original: Data, imported: RecipeImporter.Result, rebuilt: Data) {
        let (snapshot, _, _) = try TransactionComposerTests.setup()
        let original = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod).transaction
        let imported = try RecipeImporter.recipe(from: original, snapshot: snapshot, network: .preprod)
        let rebuilt = try await TransactionComposer().compose(imported.recipe, snapshot: snapshot, network: .preprod).transaction
        return (original, imported, rebuilt)
    }

    static func body(_ bytes: Data) throws -> Data {
        try TransactionValidation.decode(bytes).transactionBody.toCBORData()
    }

    @Test("A payment with a message builds the same body again")
    func payment() async throws {
        let (_, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address, lovelace: 10_000_000)],
            changeAddress: address, validUntil: 90_000_000, message: "Built by Cardano TxWorkshop",
            requiredSigners: ["04619f081850a9c468c25ac4ca72f783b6c3f006cc2dfe4e8a27fdc0"]
        )
        let (original, imported, rebuilt) = try await Self.roundTrip(recipe)
        #expect(try Self.body(rebuilt) == Self.body(original))
        let form = imported.recipe
        #expect(form.fixedInputs == [InputResolver.id(utxo.input)])
        #expect(form.sourceAddresses == [address])
        #expect(form.changeAddress == address)
        #expect(form.outputs.map(\.lovelace) == [10_000_000])
        #expect(form.message == "Built by Cardano TxWorkshop")
        #expect(form.validUntil == 90_000_000)
        #expect(form.requiredSigners == recipe.requiredSigners)
    }

    @Test("Mints, native and Plutus, build the same body again")
    func mints() async throws {
        let (_, utxo, address) = try TransactionComposerTests.setup()
        let keyHash = "04619f081850a9c468c25ac4ca72f783b6c3f006cc2dfe4e8a27fdc0"
        let native = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address,
            mints: [MintDraft(script: .native(json: #"{"type": "sig", "keyHash": "\#(keyHash)"}"#), assets: [AssetDraft(assetNameHex: "5457", quantity: 1)])]
        )
        let (nativeOriginal, nativeImported, nativeRebuilt) = try await Self.roundTrip(native)
        #expect(try Self.body(nativeRebuilt) == Self.body(nativeOriginal))
        #expect(nativeImported.recipe.mints.first?.assets.map(\.quantity) == [1])

        let plutus = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address,
            mints: [MintDraft(script: .plutus(version: 3, cborHex: try ScriptBuildingTests.alwaysSucceeds()), assets: [AssetDraft(assetNameHex: "5457", quantity: 5)], redeemer: "d87980")]
        )
        let (plutusOriginal, plutusImported, plutusRebuilt) = try await Self.roundTrip(plutus)
        #expect(try Self.body(plutusRebuilt) == Self.body(plutusOriginal))
        #expect(plutusImported.recipe.mints.first?.redeemer == "d87980")
        #expect(!plutusImported.recipe.collateral.isEmpty)
    }

    @Test("Certificates and a donation build the same body again")
    func governance() async throws {
        let (_, utxo, address) = try TransactionComposerTests.setup()
        let stake = try GovernanceBuildingTests.stakeAddress()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address,
            certificates: [
                CertificateItem(certificate: .registerStake(stakeAddress: stake)),
                CertificateItem(certificate: .delegateStake(stakeAddress: stake, pool: String(repeating: "ab", count: 28))),
                CertificateItem(certificate: .delegateVote(stakeAddress: stake, drep: "abstain")),
            ],
            donation: 1_000_000
        )
        let (original, imported, rebuilt) = try await Self.roundTrip(recipe)
        #expect(try Self.body(rebuilt) == Self.body(original))
        #expect(imported.recipe.certificates.count == 3)
        #expect(imported.recipe.donation == 1_000_000)
    }

    @Test("An output carrying a reference script keeps it")
    func referenceScript() async throws {
        let (_, utxo, address) = try TransactionComposerTests.setup()
        let script = try TransactionComposer.plutusScript(version: 3, hex: try ScriptBuildingTests.alwaysSucceeds())
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex],
            outputs: [OutputDraft(address: address, referenceScript: try TransactionComposer.referenceScriptHex(script))],
            changeAddress: address
        )
        let (original, imported, rebuilt) = try await Self.roundTrip(recipe)
        #expect(try TransactionValidation.decode(original).transactionBody.outputs.first?.script == script)
        #expect(imported.recipe.outputs.first?.referenceScript == recipe.outputs.first?.referenceScript)
        #expect(try Self.body(rebuilt) == Self.body(original))
    }

    @Test("Spending from a script keeps its script, datum and redeemer, and builds the same body again")
    func scriptInput() async throws {
        var (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let script = try TransactionComposer.plutusScript(version: 3, hex: try ScriptBuildingTests.alwaysSucceeds())
        let datum = PlutusData.bigInt(.int(42))
        let locked = UTxO(
            input: TransactionInput(transactionId: TransactionId(payload: Data(repeating: 7, count: 32)), index: 0),
            output: TransactionOutput(
                address: try Address(paymentPart: .scriptHash(try scriptHash(script: script)), network: .testnet),
                amount: Value(coin: 5_000_000),
                datumHash: DatumHash(payload: InspectionBuilder.blake2b256(try datum.toCBORData()))
            )
        )
        snapshot.utxos.append(TxDocumentCodec.hex(try locked.toCBORData()))
        let datumHex = TxDocumentCodec.hex(try datum.toCBORData())
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address, lovelace: 3_000_000)], changeAddress: address,
            scriptInputs: [ScriptInputDraft(
                input: InputResolver.id(locked.input), script: .plutus(version: 3, cborHex: try ScriptBuildingTests.alwaysSucceeds()),
                datum: datumHex, redeemer: "d87980"
            )]
        )
        let original = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod).transaction
        let imported = try RecipeImporter.recipe(from: original, snapshot: snapshot, network: .preprod).recipe
        let input = try #require(imported.scriptInputs.first)
        #expect(input.input == InputResolver.id(locked.input))
        #expect(input.datum == datumHex)
        #expect(input.redeemer == "d87980")
        #expect(imported.scriptInputs.count == 1)
        // The script UTxO is not offered to coin selection.
        #expect(!imported.fixedInputs.contains(InputResolver.id(locked.input)))
        let rebuilt = try await TransactionComposer().compose(imported, snapshot: snapshot, network: .preprod).transaction
        // Given as collateral, its key is also named as a required signer:
        // it signs either way, for the collateral.
        let (before, after) = (try TransactionValidation.decode(original).transactionBody, try TransactionValidation.decode(rebuilt).transactionBody)
        #expect(after.inputs.asArray == before.inputs.asArray)
        #expect(after.collateral?.asList == before.collateral?.asList)
        #expect(after.outputs.first == before.outputs.first)
        #expect(after.scriptDataHash == before.scriptDataHash)
        #expect(after.requiredSigners?.asList == [try #require(TransactionValidation.utxos(snapshot).first { $0.input == before.collateral?.asList.first }.flatMap {
            if case .verificationKeyHash(let hash)? = $0.output.address.paymentPart { hash } else { nil }
        })])
        let outcome = try await TransactionValidation().validate(rebuilt, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(Set(outcome.errors.map(\.kind)).isSubset(of: TransactionComposerTests.unsigned), "\(outcome.errors.map(\.message))")
    }

    @Test("A changed output is built anew: the change and fee follow")
    func edit() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address, lovelace: 10_000_000)], changeAddress: address
        )
        let original = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        var form = try RecipeImporter.recipe(from: original.transaction, snapshot: snapshot, network: .preprod).recipe
        form.outputs[0].lovelace = 20_000_000
        let edited = try await TransactionComposer().compose(form, snapshot: snapshot, network: .preprod)
        #expect(edited.totalIn == edited.totalOut + Int64(edited.fee.total))
        #expect(edited.change == original.change.map { $0 - 10_000_000 + Int64(original.fee.total) - Int64(edited.fee.total) })
        let outcome = try await TransactionValidation().validate(edited.transaction, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(Set(outcome.errors.map(\.kind)).isSubset(of: TransactionComposerTests.unsigned), "\(outcome.errors.map(\.message))")
    }

    @Test("A transaction from the chain, reading a reference input, is read into the form and builds again")
    func fromTheChain() async throws {
        let snapshot = try TransactionValidationTests.snapshot()
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let old = try TransactionValidation.decode(bytes).transactionBody
        let imported = try RecipeImporter.recipe(from: bytes, snapshot: snapshot, network: .preprod)
        #expect(imported.recipe.referenceInputs == ["16647d6365020555d905d6e0edcf08b90a567886f875b40b3d7cec1c70482624#0"])
        let rebuilt = try await TransactionComposer().compose(imported.recipe, snapshot: snapshot, network: .preprod)
        let new = try TransactionValidation.decode(rebuilt.transaction).transactionBody
        #expect(Set(new.inputs.asArray) == Set(old.inputs.asArray))
        #expect(Set(new.referenceInputs?.asList ?? []) == Set(old.referenceInputs?.asList ?? []))
        #expect(new.outputs.count == old.outputs.count)
        let outcome = try await TransactionValidation().validate(rebuilt.transaction, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(Set(outcome.errors.map(\.kind)).isSubset(of: TransactionComposerTests.unsigned), "\(outcome.errors.map(\.message))")
    }

    @Test("Inputs the chain data does not have are named")
    func missingInputs() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod).transaction
        #expect(throws: ImportError.missingInputs([InputResolver.id(utxo.input)])) {
            _ = try RecipeImporter.recipe(from: built, snapshot: nil, network: .preprod)
        }
    }

    @Test("Signatures and other metadata are noted as left out")
    func notes() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod).transaction
        var transaction = try TransactionValidation.decode(built)
        transaction.auxiliaryData = AuxiliaryData(data: .metadata(try Metadata([721: .text("nft")])))
        let notes = try RecipeImporter.recipe(from: try transaction.toCBORData(), snapshot: snapshot, network: .preprod).notes
        #expect(notes.contains { $0.kind == .dropped && $0.message.contains("721") })
    }

    @Test("A governance action the form does not offer is refused")
    func unsupported() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod).transaction
        var transaction = try TransactionValidation.decode(built)
        let account = try TransactionComposer.rewardAccount(try GovernanceBuildingTests.stakeAddress())
        let anchor = try #require(try TransactionComposer.anchor("https://example.com/a.json", String(repeating: "00", count: 32)))
        transaction.transactionBody.proposalProcedures = ProposalProcedures([
            ProposalProcedure(deposit: 1, rewardAccount: account, govAction: .noConfidence(NoConfidence(id: nil)), anchor: anchor)
        ])
        #expect(throws: ImportError.self) {
            _ = try RecipeImporter.recipe(from: try transaction.toCBORData(), snapshot: snapshot, network: .preprod)
        }
    }
}
