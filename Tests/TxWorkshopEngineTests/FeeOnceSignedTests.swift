import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// The fee is charged on the signed transaction: validation checks it as it
/// will be once signed, and a transaction made compatible with hardware
/// wallets is built again so its fee covers its new bytes.
@Suite("Fees once signed")
struct FeeOnceSignedTests {
    /// A stake registration as a byte-level CIP-21 rewrite left it: inputs and
    /// certificates as tagged sets, its fee sized for untagged certificates,
    /// so 88 lovelace short once its two keys sign. The node refused it:
    /// supplied 171529, expected 171617.
    static let shortHex =
        "84a400d901028182582077d8cd0fcfff03416252650f726791626582ae6f57c58edda269bdefd274758e0001818258390157330328870a37311d9ca0f064ac870d9a75ae436111952f999248e75a15bb387f2c67792f3143439854a4bb8cefb1259e230550b02f1b2e1a005358fd021a00029e0904d901028183078200581cc6faa2b3aefd8d833901921bb17eaa4655ad05ae7fa18506b9c4215f1a001e8480a0f5f6"
    /// The same transaction before the rewrite: certificates untagged, the
    /// fee right for these bytes.
    static var beforeRewriteHex: String { shortHex.replacingOccurrences(of: "04d90102818307", with: "04818307") }
    static let changeAddress = "0157330328870a37311d9ca0f064ac870d9a75ae436111952f999248e75a15bb387f2c67792f3143439854a4bb8cefb1259e230550b02f1b2e"
    static let fee: UInt64 = 171_529
    static let change: UInt64 = 0x5358fd

    /// The chain fixture's parameters, with a UTxO for the transaction's
    /// input at its change address.
    static func snapshot() throws -> ChainContextSnapshot {
        var snapshot = try TransactionValidationTests.snapshot()
        let utxo = UTxO(
            input: TransactionInput(
                transactionId: TransactionId(payload: try TxDocumentCodec.bytes(fromHex: "77d8cd0fcfff03416252650f726791626582ae6f57c58edda269bdefd274758e")),
                index: 0
            ),
            output: TransactionOutput(
                address: try Address(from: .bytes(try TxDocumentCodec.bytes(fromHex: changeAddress))),
                amount: Value(coin: Int64(change + fee + 2_000_000))
            )
        )
        snapshot.utxos = [try utxo.toCBORData().hex]
        snapshot.spentInputs = []
        return snapshot
    }

    @Test("Without a build form, the transaction itself is rebuilt for hardware wallets, its fee sized for its signed bytes")
    func rebuildFromTransaction() async throws {
        let before = try TxDocumentCodec.bytes(fromHex: Self.beforeRewriteHex)
        #expect(try CIP21Check.report(before).findings.map(\.rule) == ["set-tags"])
        let snapshot = try Self.snapshot()
        let parameters = try #require(TransactionValidation.protocolParameters(snapshot))

        let result = try await CIP21Rebuild.rebuild(before, recipe: nil, snapshot: snapshot, network: .preprod)
        #expect(result.source == .transaction)
        #expect(result.recipe == nil)
        #expect(result.report.isCompatible, "\(result.report.findings)")
        #expect(result.previousFee == Self.fee)

        let rebuilt = try TransactionValidation.decode(result.transaction)
        let body = rebuilt.transactionBody
        #expect(body.inputs.asArray.map(InputResolver.id) == ["77d8cd0fcfff03416252650f726791626582ae6f57c58edda269bdefd274758e#0"])
        #expect(body.certificates?.count == 1)
        #expect(body.outputs.count == 1)
        #expect(body.outputs[0].address.toBytes().hex == Self.changeAddress)
        // What came in pays the deposit, the fee and the change.
        #expect(UInt64(body.outputs[0].amount.coin) + body.fee + 2_000_000 == Self.change + Self.fee + 2_000_000)

        // Signed by both keys, witnesses tagged as the ledger writes them,
        // it pays what the node asks: the 369 bytes it refused before.
        var signed = rebuilt
        signed.transactionWitnessSet.vkeyWitnesses = .nonEmptyOrderedSet(
            NonEmptyOrderedSet([try TransactionValidation.placeholderWitness(1), try TransactionValidation.placeholderWitness(2)])
        )
        let size = try Utils.feeRelevantSize(of: signed)
        #expect(size == 369)
        // Exactly what the node asked when it refused the rewritten bytes.
        #expect(body.fee == UInt64(parameters.txFeeFixed) + UInt64(parameters.txFeePerByte) * UInt64(size))
        #expect(body.fee == 171_617)
        #expect(try CIP21Check.report(try signed.toCBORData()).isCompatible)
        // And validation finds nothing short once it is signed.
        let outcome = try await TransactionValidation().validate(result.transaction, snapshot: snapshot, network: .preprod, mode: .now)
        #expect(!outcome.issues.contains { $0.kind.hasPrefix("feeTooSmall") }, "\(outcome.issues.map(\.message))")
    }

    @Test("Rebuilding without the build form needs the inputs' UTxOs, and the form for a Plutus transaction")
    func rebuildNeeds() async throws {
        let before = try TxDocumentCodec.bytes(fromHex: Self.beforeRewriteHex)
        var bare = try Self.snapshot()
        bare.utxos = []
        await #expect(throws: RebuildError.self) {
            _ = try await CIP21Rebuild.rebuild(before, recipe: nil, snapshot: bare, network: .preprod)
        }
        let plutus = try TransactionInspectionTests.bytes("conway-tx")
        await #expect {
            _ = try await CIP21Rebuild.rebuild(plutus, recipe: nil, snapshot: try TransactionValidationTests.snapshot(), network: .preprod)
        } throws: { error in
            if case RebuildError.needsBuildForm(let reasons) = error { return reasons.contains("it runs Plutus scripts") }
            return false
        }
    }

    @Test("Validating it unsigned finds the fee short of what the signed transaction costs")
    func shortOnceSigned() async throws {
        let bytes = try TxDocumentCodec.bytes(fromHex: Self.shortHex)
        let snapshot = try Self.snapshot()
        let parameters = try #require(TransactionValidation.protocolParameters(snapshot))
        let outcome = try await TransactionValidation().validate(bytes, snapshot: snapshot, network: .preprod, mode: .now)
        let finding = try #require(outcome.errors.first { $0.kind == "feeTooSmall" }, "\(outcome.issues.map(\.kind))")
        let minimum = UInt64(parameters.txFeeFixed) + UInt64(parameters.txFeePerByte) * 369
        #expect(finding.message.contains("2 vkey witnesses still to be added"))
        #expect(finding.message.contains("FeeTooSmallUTxO"))
        #expect(finding.message.contains("\(minimum)"))
        #expect(finding.fieldPath == "transaction_body.fee")
    }

    @Test("A transaction the builder makes pays for its signatures")
    func builtPays() async throws {
        let wallet = try SigningTests.testWallet()
        let (snapshot, utxo) = try SigningTests.funded(wallet.address)
        let stakeHash = try #require(wallet.ring.paths.first { $0.value == "1852H/1815H/0H/2/0" }?.key)
        let stake = try Address(
            stakingPart: .verificationKeyHash(VerificationKeyHash(payload: try TxDocumentCodec.bytes(fromHex: stakeHash))), network: .testnet
        ).toBech32()
        let recipe = BuildRecipe(
            utxos: [utxo], changeAddress: wallet.address,
            certificates: [CertificateItem(certificate: .registerStake(stakeAddress: stake))]
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let outcome = try await TransactionValidation().validate(built.transaction, snapshot: snapshot, network: .preprod, mode: .now)
        #expect(!outcome.issues.contains { $0.kind == "feeTooSmall" }, "\(outcome.issues.map(\.message))")

        // Rebuilt for hardware wallets, it still pays.
        let rebuilt = try await CIP21Rebuild.rebuild(built.transaction, recipe: recipe, snapshot: snapshot, network: .preprod)
        let after = try await TransactionValidation().validate(rebuilt.transaction, snapshot: snapshot, network: .preprod, mode: .now)
        #expect(!after.issues.contains { $0.kind == "feeTooSmall" }, "\(after.issues.map(\.message))")
    }
}
