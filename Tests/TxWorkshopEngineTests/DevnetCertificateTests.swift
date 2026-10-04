import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// Every certificate on a Yaci DevKit devnet, as the app makes them: build
/// from a recipe, sign with a key ring, validate, submit, and check the chain.
///
/// Set `TW_DEVNET_STORE` to the devnet's store (`http://localhost:8080`); the
/// admin API is found next to it. Keys are made fresh each run and never
/// written anywhere. Constitutional committee certificates need a seated
/// member, which a new devnet has none of, so those are only checked to reach
/// the ledger and be refused for that reason.
@Suite("Devnet certificates", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TW_DEVNET_STORE"] != nil))
struct DevnetCertificateTests {
    static let store = ProcessInfo.processInfo.environment["TW_DEVNET_STORE"] ?? ""
    static let admin = ProcessInfo.processInfo.environment["TW_DEVNET_ADMIN"] ?? "http://localhost:10000"
    static let network = CardanoNetwork.custom(magic: UInt32(ProcessInfo.processInfo.environment["TW_DEVNET_MAGIC"] ?? "42") ?? 42)
    let provider = ProviderConfiguration(name: "Yaci DevKit", kind: .yaciDevKit, network: Self.network, url: URL(string: Self.store))

    /// A fresh wallet: its key ring (accounts 0 to 3), funded payment address,
    /// stake addresses by account, and DRep key hash.
    struct Wallet {
        let ring: KeyRing
        let address: String
        let stake: [String]
        let drep: String
    }

    func wallet() throws -> Wallet {
        let words = try HDWallet.generateMnemonic(wordCount: .twentyFour).joined(separator: " ")
        let ring = try KeyRing(.mnemonic(words: words, passphrase: ""), accounts: 0..<4)
        func hash(_ path: String) throws -> VerificationKeyHash {
            let hex = try #require(ring.paths.first { $0.value == path }?.key, "no key at \(path)")
            return VerificationKeyHash(payload: try TxDocumentCodec.bytes(fromHex: hex))
        }
        let address = try Address(paymentPart: .verificationKeyHash(try hash("1852H/1815H/0H/0/0")), network: .testnet).toBech32()
        let stake = try (0..<4).map {
            try Address(stakingPart: .verificationKeyHash(try hash("1852H/1815H/\($0)H/2/0")), network: .testnet).toBech32()
        }
        return Wallet(ring: ring, address: address, stake: stake, drep: try hash("1852H/1815H/0H/3/0").payload.hex)
    }

    /// Asks the DevKit to send `ada` to `address`, and waits for it.
    func fund(_ address: String, ada: Int) async throws {
        var request = URLRequest(url: URL(string: "\(Self.admin)/local-cluster/api/addresses/topup")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["address": address, "adaAmount": ada])
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        for _ in 0..<60 {
            if !(try await TransactionComposer().utxos(at: [address], provider: provider, apiKey: nil)).isEmpty { return }
            try await Task.sleep(for: .seconds(1))
        }
        Issue.record("The top-up to \(address) never arrived.")
    }

    /// Builds, signs, validates and submits `certificates` from `wallet`, then
    /// waits for the transaction on chain. Returns its id.
    @discardableResult
    func run(
        _ label: String, _ certificates: [CertificateDraft], from wallet: Wallet, extraKeys: [KeyRing] = [], expectValid: Bool = true
    ) async throws -> String {
        let recipe = BuildRecipe(
            sourceAddresses: [wallet.address], changeAddress: wallet.address, message: "TxWorkshop devnet: \(label)",
            certificates: certificates.map { CertificateItem(certificate: $0) }
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: nil, network: Self.network, provider: provider)
        let snapshot = try await ChainDataFetcher().fetch(transaction: built.transaction, provider: provider, apiKey: nil, keeping: nil)
        let needed = Set(try RequiredSignatures.analyze(built.transaction, utxos: snapshot.utxos).signers.map(\.keyHash))
        var witnesses = try wallet.ring.witnesses(for: built.transaction, needed: needed)
        for ring in extraKeys { witnesses += try ring.witnesses(for: built.transaction, needed: needed) }
        let signed = try WitnessAssembler.merge(built.transaction, adding: witnesses)
        #expect(try RequiredSignatures.analyze(signed, utxos: snapshot.utxos).isComplete, "\(label): not every signer signed")

        let outcome = try await TransactionValidation().validate(signed, snapshot: snapshot, network: Self.network, mode: .asWritten)
        if expectValid {
            #expect(outcome.errors.isEmpty, "\(label) fails validation: \(outcome.errors.map(\.message))")
        } else {
            print("  \(label) validation: \(outcome.errors.map(\.message))")
        }

        let submitter = TransactionSubmitter()
        let id = try await submitter.submit(signed, provider: provider, apiKey: nil)
        for _ in 0..<60 {
            if (try? await submitter.isOnChain(id, provider: provider, apiKey: nil)) == true {
                print("✓ \(label): \(id) (fee \(built.fee.total), deposits \(built.deposits), refunds \(built.refunds))")
                // Let the store index the change before the next build spends it.
                try await Task.sleep(for: .seconds(2))
                return id
            }
            try await Task.sleep(for: .seconds(1))
        }
        Issue.record("\(label): \(id) was not on chain after a minute")
        return id
    }

    func chain() async throws -> any ChainContext {
        try await ChainContextFactory().makeContext(for: provider, apiKey: nil)
    }

    func stakeInfo(_ address: String) async throws -> StakeAddressInfo? {
        try await chain().stakeAddressInfo(address: try Address(from: .string(address))).first
    }

    @Test("Every certificate the ledger accepts, on a devnet", .timeLimit(.minutes(15)))
    func everyCertificate() async throws {
        let wallet = try wallet()
        try await fund(wallet.address, ada: 100_000)
        let (s0, s1, s2, s3) = (wallet.stake[0], wallet.stake[1], wallet.stake[2], wallet.stake[3])

        // The pool's keys: a cold key loaded the way a user loads cold.skey,
        // and a VRF key given as its key file.
        let cold = try StakePoolKeyPair.generate()
        let coldRing = try KeyRing(.envelope(json: try #require(try cold.signingKey.toTextEnvelope())))
        let coldVkey = try #require(try cold.verificationKey.toTextEnvelope())
        let vrfVkey = try #require(try VRFKeyPair.generate().verificationKey.toTextEnvelope())
        let poolID = try PoolOperator(poolKeyHash: try cold.verificationKey.poolKeyHash()).toBech32()
        let anchorHash = String(repeating: "5a", count: 32)

        // Stake address, then a new pool owned by it.
        try await run("register stake", [.registerStake(stakeAddress: s0)], from: wallet)
        #expect(try await stakeInfo(s0) != nil)

        let pool = PoolRegistrationDraft(
            pool: coldVkey, vrfKey: vrfVkey, pledge: 1_000_000_000, cost: 170_000_000, margin: "2.5%",
            rewardAccount: s0, owners: [s0],
            relays: [
                RelayDraft(kind: .dnsName, host: "relay1.devnet.example", port: 3001),
                RelayDraft(kind: .ipv4, host: "192.0.2.10", port: 6000),
                RelayDraft(kind: .ipv6, host: "2001:db8::10", port: 6001),
                RelayDraft(kind: .srvName, host: "_cardano._tcp.devnet.example", port: nil),
            ],
            metadataURL: "https://devnet.example/pool.json", metadataHash: anchorHash
        )
        try await run("register pool", [.registerPool(pool)], from: wallet, extraKeys: [coldRing])

        // Fetch Registration: the form fills from chain, as an update.
        let registered = try #require(
            try await PoolRegistrationSource.registered(poolID, provider: provider, apiKey: nil, network: Self.network),
            "the new pool's registration was not found on chain"
        )
        #expect(registered.isUpdate)
        #expect(registered.pledge == 1_000_000_000 && registered.cost == 170_000_000)
        #expect(PoolMargin.parse(registered.margin) == PoolMargin.parse("2.5%"))
        #expect(registered.relays.count == 4)
        #expect(registered.metadataURL == "https://devnet.example/pool.json")

        // Edit it and register again: no deposit.
        var update = registered
        update.pledge = 2_000_000_000
        update.margin = "1/50"
        update.relays.removeLast()
        try await run("update pool", [.registerPool(update)], from: wallet, extraKeys: [coldRing])
        let updated = try #require(try await PoolRegistrationSource.registered(poolID, provider: provider, apiKey: nil, network: Self.network))
        #expect(updated.pledge == 2_000_000_000)
        #expect(PoolMargin.parse(updated.margin) == PoolMargin.parse("0.02"))
        #expect(updated.relays.count == 3)

        // Delegation, and the DRep.
        try await run("delegate stake", [.delegateStake(stakeAddress: s0, pool: poolID)], from: wallet)
        try await run("register DRep", [.registerDRep(keyHash: wallet.drep, anchorURL: "https://devnet.example/drep.json", anchorHash: anchorHash)], from: wallet)
        try await run("delegate votes", [.delegateVote(stakeAddress: s0, drep: wallet.drep)], from: wallet)
        try await run("delegate stake and votes", [.delegateStakeAndVote(stakeAddress: s0, pool: poolID, drep: "abstain")], from: wallet)
        try await run("update DRep", [.updateDRep(keyHash: wallet.drep, anchorURL: "https://devnet.example/drep-2.json", anchorHash: anchorHash)], from: wallet)

        // The combined certificates, each registering a new stake address.
        try await run("register and delegate stake", [.registerAndDelegateStake(stakeAddress: s1, pool: poolID)], from: wallet)
        try await run("register and delegate votes", [.registerAndDelegateVote(stakeAddress: s2, drep: wallet.drep)], from: wallet)
        try await run("deregister stake", [.deregisterStake(stakeAddress: s1)], from: wallet)
        try await run("register and delegate stake and votes", [.registerAndDelegateStakeAndVote(stakeAddress: s1, pool: poolID, drep: "no-confidence")], from: wallet)
        #expect(try await stakeInfo(s1) != nil)

        // The pre-Conway pair.
        try await run("register stake (pre-Conway)", [.registerStakeLegacy(stakeAddress: s3)], from: wallet)
        try await run("deregister stake (pre-Conway)", [.deregisterStakeLegacy(stakeAddress: s3)], from: wallet)

        // Wind down: deregister, retire the pool, retire the DRep.
        try await run("deregister stake (2)", [.deregisterStake(stakeAddress: s2)], from: wallet)
        let epoch = UInt64(try await chain().epoch())
        try await run("retire pool", [.retirePool(pool: poolID, epoch: epoch + 2)], from: wallet, extraKeys: [coldRing])
        try await run("retire DRep", [.unregisterDRep(keyHash: wallet.drep)], from: wallet)
        let drep = try? await chain().drepInfo(drep: DRep(credential: .verificationKeyHash(VerificationKeyHash(payload: try TxDocumentCodec.bytes(fromHex: wallet.drep)))))
        print("DRep after retiring: \(drep.map(String.init(describing:)) ?? "not found")")
    }

    @Test("Committee certificates reach the ledger, which wants a seated member", .timeLimit(.minutes(3)))
    func committee() async throws {
        let wallet = try wallet()
        try await fund(wallet.address, ada: 1_000)
        let cold = try CommitteeColdKeyPair.generate()
        let coldHash = try cold.verificationKey.hash().payload.hex
        let coldRing = try KeyRing(.envelope(json: try #require(try cold.signingKey.toTextEnvelope())))
        let hot = try CommitteeHotKeyPair.generate().verificationKey.hash().payload.hex

        for (label, certificate) in [
            ("authorize committee hot key", CertificateDraft.authorizeCommitteeHot(coldKey: coldHash, hotKey: hot)),
            ("resign from committee", CertificateDraft.resignCommitteeCold(coldKey: coldHash, anchorURL: "", anchorHash: "")),
        ] {
            do {
                try await run(label, [certificate], from: wallet, extraKeys: [coldRing], expectValid: false)
                Issue.record("\(label) was accepted for a key that is not on the committee")
            } catch {
                print("✓ \(label): refused by the ledger: \(String(describing: error).prefix(300))")
                #expect(String(describing: error).contains("Committee"), "\(label): \(error)")
            }
        }
    }
}
