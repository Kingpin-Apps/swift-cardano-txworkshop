import Foundation
import SwiftCardanoCore
import SwiftCardanoUPLC
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Building")
struct TransactionComposerTests {
    /// What an unsigned transaction is refused for: signatures it lacks.
    static let unsigned: Set<String> = ["missingVKeyWitness", "missingRequiredSigner", "nativeScriptFailed"]

    /// The fixture's chain data, and a key-address UTxO from it to spend.
    static func setup() throws -> (snapshot: ChainContextSnapshot, utxo: UTxO, address: String) {
        let snapshot = try TransactionValidationTests.snapshot()
        let utxos = TransactionValidation.utxos(snapshot)
        let utxo = try #require(utxos.first { $0.output.address.paymentPart.map { if case .verificationKeyHash = $0 { true } else { false } } ?? false && $0.output.amount.coin > 100_000_000 })
        return (snapshot, utxo, try utxo.output.address.toBech32())
    }

    @Test("A payment balances: inputs = outputs + fee, with change back")
    func payment() async throws {
        let (snapshot, utxo, address) = try Self.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex],
            outputs: [OutputDraft(address: address, lovelace: 10_000_000)],
            changeAddress: address,
            message: "Built by Tx Workshop"
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        #expect(built.inputs == [InputResolver.id(utxo.input)])
        #expect(built.fee.total > 150_000)
        #expect(built.totalIn == built.totalOut + Int64(built.fee.total))
        #expect(built.change != nil)

        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        #expect(inspection.summary.id == built.id)
        #expect(inspection.outputs.first?.lovelace == 10_000_000)
        #expect(inspection.metadata.first?.message == "Built by Tx Workshop")
        #expect(inspection.view.fee == built.fee.total)

        // Phase 1 finds nothing but the missing signature.
        let outcome = try await TransactionValidation().validate(built.transaction, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(outcome.errors.map(\.kind) == ["missingVKeyWitness"], "\(outcome.errors.map(\.message))")
    }

    @Test("Values build from any form: a payment key file, hex, a stake key, pool.json and a DRep key")
    func flexibleValues() async throws {
        let (snapshot, utxo, address) = try Self.setup()
        let payee: PaymentVerificationKey = try PaymentSigningKey.generate().toVerificationKey()
        let stake: StakeVerificationKey = try StakeSigningKey.generate().toVerificationKey()
        let pool = try StakePoolKeyPair.generate()
        let poolID = try PoolOperator(poolKeyHash: pool.verificationKey.poolKeyHash()).toBech32()
        let drep: DRepVerificationKey = try DRepSigningKey.generate().toVerificationKey()
        let changeHex = try Address(from: .string(address)).toBytes().hex

        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex],
            outputs: [OutputDraft(address: try #require(try payee.toTextEnvelope()), lovelace: 5_000_000)],
            changeAddress: changeHex,
            certificates: [
                CertificateItem(certificate: .registerStake(stakeAddress: try #require(try stake.toTextEnvelope()))),
                CertificateItem(certificate: .delegateStake(stakeAddress: try stake.hash().payload.hex, pool: #"{"name": "p", "id_bech": "\#(poolID)"}"#)),
                CertificateItem(certificate: .delegateVote(stakeAddress: try stake.hash().payload.hex, drep: try #require(try drep.toTextEnvelope()))),
            ]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        let enterprise = try Address(paymentPart: .verificationKeyHash(payee.hash()), network: .testnet).toBech32()
        #expect(inspection.outputs.first?.address.text == enterprise)
        #expect(inspection.outputs.last?.address.text == address)
        #expect(built.transaction.count > 0)
    }

    @Test("An output without an amount gets the least the ledger allows")
    func minimumAda() async throws {
        let (snapshot, utxo, address) = try Self.setup()
        let recipe = BuildRecipe(utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        let first = try #require(inspection.outputs.first)
        #expect(first.lovelace > 800_000 && first.lovelace < 1_500_000)
    }

    @Test("Mistakes are named")
    func mistakes() async throws {
        let (snapshot, utxo, address) = try Self.setup()
        let hex = try utxo.toCBORData().hex
        await #expect(throws: ComposeError.badAddress("nope")) {
            _ = try await TransactionComposer().compose(BuildRecipe(utxos: [hex], outputs: [OutputDraft(address: "nope")], changeAddress: address), snapshot: snapshot, network: .preprod)
        }
        do {
            _ = try await TransactionComposer().compose(BuildRecipe(utxos: [hex], outputs: [OutputDraft(address: address, lovelace: 1)], changeAddress: address), snapshot: snapshot, network: .preprod)
            Issue.record("one lovelace should be below the minimum")
        } catch ComposeError.belowMinimum(let to, let minimum) {
            #expect(to == address)
            #expect(minimum > 800_000)
        }
        await #expect(throws: ComposeError.noProtocolParameters) {
            _ = try await TransactionComposer().compose(BuildRecipe(utxos: [hex], outputs: [], changeAddress: address), snapshot: nil, network: .preprod)
        }
    }

    @Test("A long message is split into 64-byte lines")
    func messageLines() throws {
        let data = try #require(try TransactionComposer.message(String(repeating: "é", count: 40)))
        guard case .metadata(let metadata) = data.data, case .map(let map)? = metadata[674], case .list(let lines)? = map[.text("msg")] else {
            Issue.record("expected a CIP-20 message")
            return
        }
        #expect(lines.count == 2)
        #expect(try TransactionComposer.message("  \n") == nil)
    }
}

@Suite("Building with scripts")
struct ScriptBuildingTests {
    /// An always-succeeding PlutusV3 minting policy, as `compiledCode` hex.
    static func alwaysSucceeds() throws -> String {
        var parser = UPLCParser()
        let program = try DeBruijnConverter().convert(try parser.parse("(program 1.1.0 (lam ctx (con unit ())))"))
        let flat = try FlatEncoder().encode(program)
        return try Primitive.bytes(flat).toCBORData().hex
    }

    @Test("A native-script mint is signed for by the key it names")
    func nativeMint() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let keyHash = "04619f081850a9c468c25ac4ca72f783b6c3f006cc2dfe4e8a27fdc0"
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex],
            outputs: [OutputDraft(address: address)],
            changeAddress: address,
            mints: [MintDraft(script: .native(json: #"{"type": "sig", "keyHash": "\#(keyHash)"}"#), assets: [AssetDraft(assetNameHex: "5457", quantity: 1)])]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        #expect(inspection.mint.map(\.assetNameHex) == ["5457"])
        #expect(inspection.scripts.map(\.language) == ["native"])
        let outcome = try await TransactionValidation().validate(built.transaction, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(Set(outcome.errors.map(\.kind)).isSubset(of: TransactionComposerTests.unsigned), "\(outcome.errors.map(\.message))")
    }

    @Test("A Plutus mint gets its execution units, collateral and script data hash")
    func plutusMint() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex],
            outputs: [OutputDraft(address: address)],
            changeAddress: address,
            mints: [MintDraft(script: .plutus(version: 3, cborHex: try Self.alwaysSucceeds()), assets: [AssetDraft(assetNameHex: "5457", quantity: 5)], redeemer: "d87980")]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        #expect(built.fee.steps > 0)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        #expect(!inspection.collateralInputs.isEmpty)
        #expect(inspection.redeemers.count == 1)
        let outcome = try await TransactionValidation().validate(built.transaction, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(Set(outcome.errors.map(\.kind)).isSubset(of: TransactionComposerTests.unsigned), "\(outcome.errors.map(\.message))")
        let run = try #require(outcome.redeemers.first)
        #expect(run.passed)
        #expect(!run.exceedsDeclared)
    }

    @Test("Bad scripts and data are named")
    func badScripts() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        func recipe(_ mint: MintDraft) throws -> BuildRecipe {
            BuildRecipe(utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address, mints: [mint])
        }
        await #expect(throws: ComposeError.self) {
            _ = try await TransactionComposer().compose(try recipe(MintDraft(script: .native(json: "{"), assets: [AssetDraft(assetNameHex: "00")])), snapshot: snapshot, network: .preprod)
        }
        await #expect(throws: ComposeError.badPlutusData("the minting redeemer")) {
            _ = try await TransactionComposer().compose(try recipe(MintDraft(script: .plutus(version: 3, cborHex: try Self.alwaysSucceeds()), assets: [AssetDraft(assetNameHex: "00")], redeemer: "zz")), snapshot: snapshot, network: .preprod)
        }
    }
}

@Suite("Building governance")
struct GovernanceBuildingTests {
    static func stakeAddress() throws -> String {
        let hash = VerificationKeyHash(payload: try TxDocumentCodec.bytes(fromHex: "04619f081850a9c468c25ac4ca72f783b6c3f006cc2dfe4e8a27fdc0"))
        return try Address(stakingPart: .verificationKeyHash(hash), network: .testnet).toBech32()
    }

    @Test("Registering and delegating pays the stake deposit, and the value balances")
    func registerAndDelegate() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let stake = try Self.stakeAddress()
        let pool = String(repeating: "ab", count: 28)
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex],
            outputs: [OutputDraft(address: address)],
            changeAddress: address,
            certificates: [
                CertificateItem(certificate: .registerStake(stakeAddress: stake)),
                CertificateItem(certificate: .delegateStake(stakeAddress: stake, pool: pool)),
                CertificateItem(certificate: .delegateVote(stakeAddress: stake, drep: "abstain")),
            ]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let parameters = try #require(TransactionValidation.protocolParameters(snapshot))
        #expect(built.deposits == parameters.stakeAddressDeposit)
        #expect(built.totalIn == built.totalOut + Int64(built.fee.total) + built.deposits)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        #expect(inspection.view.certificates.count == 3)
        let outcome = try await TransactionValidation().validate(built.transaction, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(!outcome.errors.contains { $0.kind == "valueNotConserved" || $0.kind == "feeTooSmall" })
    }

    @Test("A treasury donation comes out of the change and decodes")
    func donation() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address, donation: 1_000_000
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        #expect(built.totalIn == built.totalOut + Int64(built.fee.total) + 1_000_000)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        #expect(inspection.view.treasuryDonation == 1_000_000)
    }

    @Test("Governance mistakes are named")
    func mistakes() throws {
        #expect(throws: ComposeError.self) { _ = try TransactionComposer.rewardAccount("addr_test1vqzxr8cgrpg2n3rgcfdvfjnj77pmdslsqmxzmljw3gnlmsqyskzqq") }
        #expect(throws: ComposeError.self) { _ = try TransactionComposer.govActionID("abc#1") }
        #expect(throws: ComposeError.self) { _ = try TransactionComposer.anchor("https://example.com", "00") }
        #expect(try TransactionComposer.anchor("", "") == nil)
        #expect(try TransactionComposer.drep("abstain").credential == .alwaysAbstain)
    }
}
