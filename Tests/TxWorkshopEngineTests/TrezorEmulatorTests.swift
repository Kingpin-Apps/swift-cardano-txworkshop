import CardanoHWKit
import CardanoHWWalletTrezor
import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// The app's whole Trezor path against real firmware: the trezor-user-env
/// emulator, seeded by swift-cardano-hw-wallet's Tools/emulator/bootstrap.mjs.
/// Set `TREZOR_EMULATOR=1` to run.
@Suite("Trezor emulator", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TREZOR_EMULATOR"] != nil))
struct TrezorEmulatorTests {
    @Test("A payment built here is signed on the device and validates in full")
    func signPayment() async throws {
        let bridge = TrezorEmulatorBridge()
        let network = TrezorNetwork(networkId: 0, protocolMagic: 1)
        let account = try await TrezorSignSession(transport: bridge, network: network, options: TrezorSigningOptions(tagCborSets: false))
            .importAccount(network: .testnet, accountIndex: 0)
        let derivation = try PublicHDDerivation(account: account)
        let address = try derivation.address(role: 0, index: 0)

        var snapshot = try TransactionValidationTests.snapshot()
        let utxo = UTxO(
            input: TransactionInput(transactionId: TransactionId(payload: Data(repeating: 9, count: 32)), index: 0),
            output: TransactionOutput(address: try Address(from: .string(address)), amount: Value(coin: 50_000_000))
        )
        snapshot.utxos = [try utxo.toCBORData().hex]
        snapshot.spentInputs = []
        let recipe = BuildRecipe(utxos: snapshot.utxos, outputs: [OutputDraft(address: address, lovelace: 3_000_000)], changeAddress: address)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)

        let signer = TrezorSignSession(
            transport: bridge, network: network,
            options: TrezorSigningOptions(tagCborSets: HardwareSigning.usesTaggedSets(built.transaction))
        )
        let witnesses = try await HardwareSigning().sign(built.transaction, utxos: snapshot.utxos, account: account, signer: signer)
        await bridge.release()
        #expect(witnesses.count == 1)
        #expect(witnesses.allSatisfy { WitnessAssembler.verifies($0, for: built.transaction) })

        let signed = try WitnessAssembler.merge(built.transaction, adding: witnesses)
        #expect(try await TransactionInspector().inspect(signed).id == built.id)
        #expect(try RequiredSignatures.analyze(signed, utxos: snapshot.utxos).isComplete)
        let outcome = try await TransactionValidation().validate(signed, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(outcome.errors.isEmpty, "\(outcome.errors.map(\.message))")
    }
}
