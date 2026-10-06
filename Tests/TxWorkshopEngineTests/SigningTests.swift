import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Signing")
struct SigningTests {
    /// A fresh wallet for each run; never a real one.
    static func testWallet() throws -> (material: SigningKeyMaterial, ring: KeyRing, address: String, keyHash: String) {
        let words = try HDWallet.generateMnemonic(wordCount: .fifteen).joined(separator: " ")
        let material = SigningKeyMaterial.mnemonic(words: words, passphrase: "")
        let ring = try KeyRing(material)
        let keyHash = try #require(ring.paths.first { $0.value == "1852H/1815H/0H/0/0" }?.key)
        let address = try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: try TxDocumentCodec.bytes(fromHex: keyHash))),
            network: .testnet
        ).toBech32()
        return (material, ring, address, keyHash)
    }

    /// A made-up UTxO of 100 ada at `address`, with the fixture's protocol
    /// parameters.
    static func funded(_ address: String) throws -> (snapshot: ChainContextSnapshot, utxo: String) {
        var snapshot = try TransactionValidationTests.snapshot()
        let utxo = UTxO(
            input: TransactionInput(transactionId: TransactionId(payload: Data((0..<32).map { _ in UInt8.random(in: 0...255) })), index: 0),
            output: TransactionOutput(address: try Address(from: .string(address)), amount: Value(coin: 100_000_000))
        )
        let hex = try utxo.toCBORData().hex
        snapshot.utxos = [hex]
        snapshot.spentInputs = []
        return (snapshot, hex)
    }

    @Test("A mnemonic key signs a built transaction, which then validates in full")
    func signAndValidate() async throws {
        let wallet = try Self.testWallet()
        let (snapshot, utxo) = try Self.funded(wallet.address)
        let recipe = BuildRecipe(utxos: [utxo], outputs: [OutputDraft(address: wallet.address, lovelace: 5_000_000)], changeAddress: wallet.address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)

        let needed = try RequiredSignatures.analyze(built.transaction, utxos: snapshot.utxos)
        #expect(needed.signers.map(\.keyHash) == [wallet.keyHash])
        #expect(!needed.isComplete)

        let witnesses = try wallet.ring.witnesses(for: built.transaction, needed: Set(needed.signers.map(\.keyHash)))
        #expect(witnesses.count == 1)
        #expect(WitnessAssembler.verifies(witnesses[0], for: built.transaction))
        let signed = try WitnessAssembler.merge(built.transaction, adding: witnesses)
        #expect(try await TransactionInspector().inspect(signed).id == built.id)
        #expect(try RequiredSignatures.analyze(signed, utxos: snapshot.utxos).isComplete)

        let outcome = try await TransactionValidation().validate(signed, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(outcome.errors.isEmpty, "\(outcome.errors.map(\.message))")
        // Signing again adds nothing.
        #expect(try WitnessAssembler.merge(signed, adding: witnesses) == signed)
    }

    @Test("Adding a witness keeps the body and every other witness byte for byte")
    func preservesBytes() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let wallet = try Self.testWallet()
        let transaction = try TransactionValidation.decode(bytes)
        let extra = VerificationKeyWitness(
            vkey: try wallet.ring.keys[wallet.keyHash]!.toVerificationKeyType(),
            signature: try wallet.ring.keys[wallet.keyHash]!.sign(data: transaction.id!.payload)
        )
        let merged = try WitnessAssembler.merge(bytes, adding: [extra])
        let originalID = try await TransactionInspector().inspect(bytes).id
        #expect(try await TransactionInspector().inspect(merged).id == originalID)
        #expect(try WitnessAssembler.existing(in: merged).count == 2)
        let before = try TransactionValidation.decode(bytes).transactionWitnessSet
        let after = try TransactionValidation.decode(merged).transactionWitnessSet
        #expect(try before.plutusData?.toCBORData() == after.plutusData?.toCBORData())
        #expect(try before.redeemers?.toCBORData() == after.redeemers?.toCBORData())
        // The order still runs: the script data hash covers unchanged bytes.
        let outcome = try await TransactionValidation().validate(merged, snapshot: try TransactionValidationTests.snapshot(), network: .preprod, mode: .asWritten)
        let allPass = outcome.redeemers.allSatisfy { $0.passed }
        #expect(allPass)
    }

    @Test("Removing a witness takes out only its signature, and keeps the id")
    func removesWitness() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let wallet = try Self.testWallet()
        let transaction = try TransactionValidation.decode(bytes)
        let extra = VerificationKeyWitness(
            vkey: try wallet.ring.keys[wallet.keyHash]!.toVerificationKeyType(),
            signature: try wallet.ring.keys[wallet.keyHash]!.sign(data: transaction.id!.payload)
        )
        let merged = try WitnessAssembler.merge(bytes, adding: [extra])
        let removed = try WitnessAssembler.remove(merged, keyHashes: [try WitnessAssembler.keyHash(extra)])
        // Back to exactly what it was before the witness was added.
        #expect(removed == bytes)
        #expect(try await TransactionInspector().inspect(removed).id == (try await TransactionInspector().inspect(bytes).id))

        // The last witness gone: no vkey witnesses left at all.
        let original = try WitnessAssembler.existing(in: bytes).map(WitnessAssembler.keyHash)
        let bare = try WitnessAssembler.remove(bytes, keyHashes: Set(original))
        #expect(try WitnessAssembler.existing(in: bare).isEmpty)
        #expect(try await TransactionInspector().inspect(bare).id == (try await TransactionInspector().inspect(bytes).id))
    }

    @Test("Witnesses read from a witness set, a single witness, or a cardano-cli file")
    func importWitnesses() throws {
        let wallet = try Self.testWallet()
        let key = wallet.ring.keys[wallet.keyHash]!
        let witness = VerificationKeyWitness(vkey: try key.toVerificationKeyType(), signature: try key.sign(data: Data(repeating: 1, count: 32)))
        let single = try witness.toCBORData().hex
        #expect(try WitnessAssembler.witnesses(from: single).count == 1)
        var set = TransactionWitnessSet()
        set.vkeyWitnesses = .list([witness])
        #expect(try WitnessAssembler.witnesses(from: try set.toCBORData().hex).count == 1)
        let cli = try Primitive.list([.uint(0), witness.toPrimitive()]).toCBORData().hex
        let file = #"{"type": "TxWitness ConwayEra", "description": "Key Witness ShelleyEra", "cborHex": "\#(cli)"}"#
        #expect(try WitnessAssembler.keyHash(try WitnessAssembler.witnesses(from: file)[0]) == wallet.keyHash)
        #expect(throws: WitnessError.unreadable) { _ = try WitnessAssembler.witnesses(from: "zz") }
    }

    @Test("A signing key envelope loads, and bad material is refused")
    func materials() throws {
        #expect(throws: KeyRingError.badMnemonic) { _ = try KeyRing(.mnemonic(words: "not a phrase", passphrase: "")) }
        #expect(throws: KeyRingError.self) { _ = try KeyRing(.envelope(json: "{}")) }
        let wallet = try Self.testWallet()
        let key = wallet.ring.keys[wallet.keyHash]!
        guard case .extendedSigningKey(let extended) = key, let payment = extended as? PaymentExtendedSigningKey else {
            Issue.record("expected an extended payment key")
            return
        }
        let envelope = try payment.toTextEnvelope() ?? ""
        let ring = try KeyRing(.envelope(json: envelope))
        #expect(ring.keyHashes == [wallet.keyHash])
    }
}

@Suite("Submitting")
struct SubmittingTests {
    /// A chain that accepts what is submitted and then knows it.
    final class Chain: @unchecked Sendable {
        var submitted: Data?
    }

    struct Context: ChainContext {
        let chain: Chain
        var name: String { "stub" }
        var type: ContextType { .online }
        var networkId: NetworkId { .testnet }
        func submitTxCBOR(cbor: Data) async throws -> String {
            chain.submitted = cbor
            return "\"" + (try Transaction.fromCBOR(data: cbor).id?.payload.hex ?? "") + "\""
        }
        func utxo(input: TransactionInput) async throws -> (UTxO, isSpent: Bool)? {
            guard let bytes = chain.submitted, let transaction = try? Transaction.fromCBOR(data: bytes),
                transaction.id == input.transactionId
            else { return nil }
            return (UTxO(input: input, output: transaction.transactionBody.outputs[0]), false)
        }
        func protocolParameters() async throws -> ProtocolParameters { throw CardanoChainError.notImplemented(nil) }
        func genesisParameters() async throws -> GenesisParameters { throw CardanoChainError.notImplemented(nil) }
        func epoch() async throws -> Int { 0 }
        func era() async throws -> Era? { nil }
        func lastBlockSlot() async throws -> Int { 0 }
    }

    @Test("A submitted transaction is reported by id, then found on chain")
    func submitAndConfirm() async throws {
        let chain = Chain()
        let submitter = TransactionSubmitter { _, _ in Context(chain: chain) }
        let provider = ProviderConfiguration(name: "stub", kind: .koios, network: .preprod)
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let id = try await TransactionInspector().inspect(bytes).id
        #expect(try await !submitter.isOnChain(id, provider: provider, apiKey: nil))
        #expect(try await submitter.submit(bytes, provider: provider, apiKey: nil) == id)
        #expect(chain.submitted == bytes)
        #expect(try await submitter.isOnChain(id, provider: provider, apiKey: nil))
    }
}
