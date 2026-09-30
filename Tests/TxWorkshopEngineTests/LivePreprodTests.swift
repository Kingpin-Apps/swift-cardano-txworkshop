import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// The whole loop on preprod, as the app runs it: build from the chain, sign
/// with a key, validate, submit, and wait for it on chain.
///
/// Set `TW_PREPROD_WALLET` to a file holding a test wallet's recovery phrase,
/// kept outside the repo. If the file doesn't exist, the first test makes a
/// new wallet there and prints its address, to fund from the preprod faucet.
/// Each run sends 2 ada from the wallet back to itself, so it only costs fees.
@Suite("Live preprod", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TW_PREPROD_WALLET"] != nil))
struct LivePreprodTests {
    let walletFile = URL(filePath: ((ProcessInfo.processInfo.environment["TW_PREPROD_WALLET"] ?? "") as NSString).expandingTildeInPath)
    let provider = ProviderConfiguration(name: "Koios (public)", kind: .koios, network: .preprod)

    /// The wallet's phrase, making and saving one if there is none yet.
    func phrase() throws -> String {
        if let saved = try? String(contentsOf: walletFile, encoding: .utf8) {
            return saved.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let words = try HDWallet.generateMnemonic(wordCount: .twentyFour).joined(separator: " ")
        try FileManager.default.createDirectory(at: walletFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try words.write(to: walletFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: walletFile.path())
        return words
    }

    /// The wallet's key ring and its first address, which gets the funds.
    func wallet() throws -> (ring: KeyRing, address: String) {
        let ring = try KeyRing(.mnemonic(words: try phrase(), passphrase: ""))
        let keyHash = try #require(ring.paths.first { $0.value == "1852H/1815H/0H/0/0" }?.key)
        let address = try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: try TxDocumentCodec.bytes(fromHex: keyHash))),
            network: .testnet
        ).toBech32()
        return (ring, address)
    }

    @Test("The test wallet exists, and its address can be funded")
    func address() throws {
        let (_, address) = try wallet()
        print("PREPROD TEST WALLET: \(address)")
        print("Fund it at https://docs.cardano.org/cardano-testnets/tools/faucet (Preprod).")
    }

    @Test("Build, sign, validate, submit and see it on chain", .timeLimit(.minutes(10)))
    func endToEnd() async throws {
        let (ring, address) = try wallet()
        let recipe = BuildRecipe(
            sourceAddresses: [address],
            outputs: [OutputDraft(address: address, lovelace: 2_000_000)],
            changeAddress: address,
            message: "Cardano TxWorkshop preprod end-to-end test"
        )

        // Build from the wallet's UTxOs on chain.
        let built = try await TransactionComposer().compose(recipe, snapshot: nil, network: .preprod, provider: provider)
        print("Built \(built.id): fee \(built.fee.total), \(built.inputs.count) input(s)")

        // Sign as the Sign & Submit screen does.
        let snapshot = try await ChainDataFetcher().fetch(transaction: built.transaction, provider: provider, apiKey: nil, keeping: nil)
        let needed = try RequiredSignatures.analyze(built.transaction, utxos: snapshot.utxos)
        let witnesses = try ring.witnesses(for: built.transaction, needed: Set(needed.signers.map(\.keyHash)))
        let signed = try WitnessAssembler.merge(built.transaction, adding: witnesses)
        #expect(try RequiredSignatures.analyze(signed, utxos: snapshot.utxos).isComplete)

        // Validate against the chain before sending.
        let outcome = try await TransactionValidation().validate(signed, snapshot: snapshot, network: .preprod, mode: .asWritten)
        #expect(outcome.errors.isEmpty, "\(outcome.errors.map(\.message))")

        // Submit, then wait for it to be on chain.
        let submitter = TransactionSubmitter()
        let id = try await submitter.submit(signed, provider: provider, apiKey: nil)
        #expect(id == built.id)
        print("Submitted \(id)")
        var onChain = false
        for _ in 0..<40 where !onChain {
            try await Task.sleep(for: .seconds(15))
            onChain = (try? await submitter.isOnChain(id, provider: provider, apiKey: nil)) ?? false
        }
        #expect(onChain, "\(id) was not on chain after 10 minutes")
        print("On chain: https://preprod.cardanoscan.io/transaction/\(id)")
    }
}
