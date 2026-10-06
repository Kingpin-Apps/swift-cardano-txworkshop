import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Reading values in any form")
struct ValueReaderTests {
    static func envelope(_ key: some PayloadCBORSerializable) throws -> String {
        try #require(try key.toTextEnvelope())
    }

    static func read(_ kind: ValueKind, _ text: String, network: CardanoNetwork? = .preprod) throws -> ReadValue {
        try ValueReader.read(kind, text: text, network: network)
    }

    @Test("Addresses: bech32, hex, and payment keys, on the right network")
    func addresses() throws {
        let signing = try PaymentSigningKey.generate()
        let verification: PaymentVerificationKey = try signing.toVerificationKey()
        let enterprise = try Address(paymentPart: .verificationKeyHash(verification.hash()), network: .testnet)
        let bech32 = try enterprise.toBech32()

        #expect(try Self.read(.address, bech32).value == bech32)
        #expect(try Self.read(.address, "0x" + enterprise.toBytes().hex).value == bech32)
        #expect(try Self.read(.address, Self.envelope(verification)).value == bech32)
        #expect(try Self.read(.address, Self.envelope(signing)).value == bech32)

        let stake = try Address(stakingPart: .verificationKeyHash(verification.hash()), network: .testnet)
        #expect(throws: ValueReadError.self) { try Self.read(.address, try stake.toBech32()) }
        #expect(throws: ValueReadError.self) { try Self.read(.address, bech32, network: .mainnet) }
        #expect(throws: ValueReadError.self) { try Self.read(.address, Self.envelope(verification), network: nil) }
    }

    @Test("Stake addresses: stake keys, key hashes and base addresses")
    func stakeAddresses() throws {
        let signing = try StakeSigningKey.generate()
        let verification: StakeVerificationKey = try signing.toVerificationKey()
        let hash = try verification.hash()
        let expected = try Address(stakingPart: .verificationKeyHash(hash), network: .testnet).toBech32()

        #expect(try Self.read(.stakeAddress, Self.envelope(verification)).value == expected)
        #expect(try Self.read(.stakeAddress, Self.envelope(signing)).value == expected)
        #expect(try Self.read(.stakeAddress, hash.payload.hex).value == expected)
        #expect(try Self.read(.stakeAddress, expected).value == expected)

        let payment = try Address(paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 1, count: 28))), stakingPart: .verificationKeyHash(hash), network: .testnet)
        #expect(try Self.read(.stakeAddress, payment.toBech32()).value == expected)
        #expect(throws: ValueReadError.self) { try Self.read(.stakeAddress, Self.envelope(PaymentVerificationKey(payload: verification.payload))) }
    }

    @Test("Pools: ids, hex, cold keys and pool.json")
    func pools() throws {
        let keys = try StakePoolKeyPair.generate()
        let hash = try keys.verificationKey.poolKeyHash()
        let id = try PoolOperator(poolKeyHash: hash).toBech32()

        #expect(try Self.read(.pool, id).value == id)
        #expect(try Self.read(.pool, hash.payload.hex).value == id)
        #expect(try Self.read(.pool, keys.verificationKey.payload.hex).value == id)
        #expect(try Self.read(.pool, Self.envelope(keys.verificationKey)).value == id)
        #expect(try Self.read(.pool, Self.envelope(keys.signingKey)).value == id)
        #expect(try Self.read(.pool, #"{"name": "alice", "id_bech": "\#(id)"}"#).value == id)
        #expect(try Self.read(.pool, #"{"name": "alice", "id_hex": "\#(hash.payload.hex)"}"#).value == id)
        #expect(throws: ValueReadError.self) { try Self.read(.pool, "pool1nope") }

        // A pool.json that names its cold key by path, read from its folder.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.envelope(keys.verificationKey).write(to: folder.appendingPathComponent("cold.vkey"), atomically: true, encoding: .utf8)
        let poolJSON = Data(#"{"name": "alice", "cold_vkey": "cold.vkey", "pledge": 100}"#.utf8)
        let fromFile = try ValueReader.read(.pool, file: poolJSON, name: "alice.pool.json", network: nil, folder: folder)
        #expect(fromFile.value == id)
        #expect(fromFile.form.contains("alice.pool.json"))
        // Without the folder, it says which file it needs.
        #expect(throws: ValueReadError.self) { try ValueReader.read(.pool, file: poolJSON, name: "alice.pool.json", network: nil) }
        // The metadata JSON doesn't name a pool, and says so.
        let metadata = Data(#"{"name": "Alice", "ticker": "ALICE", "homepage": "https://example.com", "description": ""}"#.utf8)
        #expect {
            try ValueReader.read(.pool, file: metadata, name: "alice.metadata.json", network: nil)
        } throws: { "\($0)".contains("metadata") }
    }

    @Test("DReps: special values, ids, hex and key files")
    func dreps() throws {
        let signing = try DRepSigningKey.generate()
        let verification: DRepVerificationKey = try signing.toVerificationKey()
        let hash = try verification.hash()
        let id = try DRep(credential: .verificationKeyHash(hash)).id()

        #expect(try Self.read(.drep, "Abstain").value == "abstain")
        #expect(try Self.read(.drep, "always-no-confidence").value == "no-confidence")
        #expect(try Self.read(.drep, id).value == id)
        #expect(try Self.read(.drep, hash.payload.hex).value == id)
        #expect(try Self.read(.drep, Self.envelope(verification)).value == id)
        #expect(try Self.read(.drep, Self.envelope(signing)).value == id)

        #expect(try Self.read(.drepKeyHash, id).value == hash.payload.hex)
        #expect(try Self.read(.drepKeyHash, Self.envelope(signing)).value == hash.payload.hex)
    }

    @Test("Required signers: any key file, hex, or an address's payment key")
    func keyHashes() throws {
        let signing = try PaymentSigningKey.generate()
        let verification: PaymentVerificationKey = try signing.toVerificationKey()
        let hash = try verification.hash().payload.hex
        let address = try Address(paymentPart: .verificationKeyHash(verification.hash()), network: .testnet).toBech32()
        #expect(try Self.read(.keyHash, Self.envelope(signing)).value == hash)
        #expect(try Self.read(.keyHash, hash).value == hash)
        #expect(try Self.read(.keyHash, address).value == hash)
        let drep: DRepVerificationKey = try DRepSigningKey.generate().toVerificationKey()
        #expect(try Self.read(.keyHash, Self.envelope(drep)).value == drep.hash().payload.hex)
    }

    @Test("Committee hot keys, governance actions and anchor hashes")
    func governance() throws {
        let hot = try CommitteeHotSigningKey.generate()
        let hotVerification: CommitteeHotVerificationKey = try hot.toVerificationKey()
        #expect(try Self.read(.committeeHotKeyHash, Self.envelope(hotVerification)).value == hotVerification.hash().payload.hex)

        let txID = String(repeating: "ab", count: 32)
        let action = GovActionID(transactionID: TransactionId(payload: Data(repeating: 0xab, count: 32)), govActionIndex: 3)
        #expect(try Self.read(.govActionID, "\(txID)#3").value == "\(txID)#3")
        #expect(try Self.read(.govActionID, action.toBech32()).value == "\(txID)#3")

        let anchor = Data("{\"rationale\": \"yes\"}".utf8)
        let hashed = try ValueReader.read(.anchorHash, file: anchor, name: "rationale.jsonld", network: nil)
        #expect(hashed.value.count == 64)
        #expect(try Self.read(.anchorHash, hashed.value).value == hashed.value)
    }

    @Test("Policy ids from scripts, asset names as text or hex, Plutus data in any form")
    func assetsAndData() throws {
        let keyHash = String(repeating: "12", count: 28)
        let native = #"{"type": "sig", "keyHash": "\#(keyHash)"}"#
        let policy = try Self.read(.policyID, native)
        #expect(policy.value == (try scriptHash(script: .nativeScript(NativeScript.fromJSON(native))).payload.hex))

        #expect(try Self.read(.assetName, "TOKEN").value == Data("TOKEN".utf8).hex)
        #expect(try Self.read(.assetName, "cafe").value == "cafe")
        #expect(try Self.read(.assetName, "\"cafe\"").value == Data("cafe".utf8).hex)

        let integer = try Self.read(.plutusData, "42")
        #expect(try Self.read(.plutusData, #"{"int": 42}"#).value == integer.value)
        #expect(try Self.read(.plutusData, integer.value).value == integer.value)
        #expect(throws: ValueReadError.self) { try Self.read(.plutusData, "not data") }
    }
}
