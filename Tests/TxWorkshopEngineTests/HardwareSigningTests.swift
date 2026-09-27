import CardanoHWKit
import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// Checked against firmware: the account key and address trezor-user-env
/// returned for its test seed (swift-cardano-hw-wallet's
/// TrezorEmulatorVectorsTests).
@Suite("Hardware signing")
struct HardwareSigningTests {
    static let seed = Array(repeating: "all", count: 12).joined(separator: " ")
    static let xpub = "d507c8f866691bd96e131334c355188b1a1d0b2fa0ab11545075aab332d77d9eb19657ad13ee581b56b0f8d744d66ca356b93d42fe176b3de007d53e9c4c4e7a"
    static let deviceAddress = "addr1qxq0nckg3ekgzuqg7w5p9mvgnd9ym28qh5grlph8xd2z92sj922xhxkn6twlq2wn4q50q352annk3903tj00h45mgfmsl3s9zt"

    static func account() throws -> HardwareAccountModel {
        HardwareAccountModel(
            deviceKind: .trezor, accountXPub: try TxDocumentCodec.bytes(fromHex: xpub), masterFingerprint: Data(),
            accountPath: "m/1852'/1815'/0'", network: .mainnet
        )
    }

    @Test("The device's account keys are the ones the app derives from the same seed")
    func keysMatchSoftware() throws {
        let hardware = try HardwareSigning.keyHashes(of: try Self.account())
        let software = try KeyRing(.mnemonic(words: Self.seed, passphrase: "")).keyHashes
        #expect(hardware.count == 41)
        #expect(hardware.isSubset(of: software))
    }

    @Test("A request names the device's own path for the address it spends from")
    func request() async throws {
        let account = try Self.account()
        #expect(try HardwareSigning.addressPaths(account)[Self.deviceAddress] == "m/1852'/1815'/0'/0/0")

        var snapshot = try TransactionValidationTests.snapshot()
        let utxo = UTxO(
            input: TransactionInput(transactionId: TransactionId(payload: Data(repeating: 7, count: 32)), index: 0),
            output: TransactionOutput(address: try Address(from: .string(Self.deviceAddress)), amount: Value(coin: 50_000_000))
        )
        snapshot.utxos = [try utxo.toCBORData().hex]
        let recipe = BuildRecipe(
            utxos: snapshot.utxos, outputs: [OutputDraft(address: Self.deviceAddress, lovelace: 2_000_000)], changeAddress: Self.deviceAddress
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .mainnet)
        let request = try HardwareSigning.request(for: built.transaction, utxos: snapshot.utxos, account: account)
        #expect(request.spentUTxOs.map { InputResolver.id($0.input) } == [InputResolver.id(utxo.input)])
        #expect(request.certificates.isEmpty)
        #expect(request.unsigned.id?.payload.hex == built.id)
        // txbuilder writes its sets with tag 258, as Conway transactions on
        // chain usually do; Alonzo ones do not.
        #expect(HardwareSigning.usesTaggedSets(built.transaction))
        #expect(HardwareSigning.usesTaggedSets(try TransactionInspectionTests.bytes("conway-tx")))
        #expect(!HardwareSigning.usesTaggedSets(try TransactionInspectionTests.bytes("alonzo-plutus-v1")))

        // A stranger's address has no path on this account.
        let stranger = try SigningTests.testWallet().address
        #expect(throws: HardwareSigningError.self) {
            let other = UTxO(input: utxo.input, output: TransactionOutput(address: try Address(from: .string(stranger)), amount: Value(coin: 50_000_000)))
            _ = try HardwareSigning.request(for: built.transaction, utxos: [try other.toCBORData().hex], account: account)
        }
        #expect(throws: HardwareSigningError.unknownInput(InputResolver.id(utxo.input))) {
            _ = try HardwareSigning.request(for: built.transaction, utxos: [], account: account)
        }
    }
}
