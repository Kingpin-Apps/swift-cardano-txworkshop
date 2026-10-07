import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// Certificates read from files: whatever the form builds, written as a
/// cardano-cli certificate file and read back, builds the same certificate.
@Suite("Certificate files")
struct CertificateFileTests {
    let pool = String(repeating: "ab", count: 28)
    let drepKey = String(repeating: "56", count: 28)
    let anchorHash = String(repeating: "78", count: 32)

    /// The certificates `drafts` build, in order.
    func certificates(_ drafts: [CertificateDraft]) async throws -> [Certificate] {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address,
            certificates: drafts.map { CertificateItem(certificate: $0) }
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        return try TransactionValidation.decode(built.transaction).transactionBody.certificates?.asList ?? []
    }

    /// `certificate` as cardano-cli writes it.
    func envelope(_ certificate: Certificate) throws -> Data {
        let json: [String: String] = [
            "type": "CertificateConway", "description": "Certificate", "cborHex": try certificate.toCBORData().hex,
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test("Every certificate the form builds reads back from its file, and builds the same again")
    func roundTrip() async throws {
        let stake = try GovernanceBuildingTests.stakeAddress()
        let drafts: [CertificateDraft] = [
            .registerStake(stakeAddress: stake),
            .deregisterStake(stakeAddress: stake),
            .registerStakeLegacy(stakeAddress: stake),
            .deregisterStakeLegacy(stakeAddress: stake),
            .delegateStake(stakeAddress: stake, pool: pool),
            .delegateVote(stakeAddress: stake, drep: drepKey),
            .delegateStakeAndVote(stakeAddress: stake, pool: pool, drep: "no-confidence"),
            .registerAndDelegateStake(stakeAddress: stake, pool: pool),
            .registerAndDelegateVote(stakeAddress: stake, drep: "abstain"),
            .registerAndDelegateStakeAndVote(stakeAddress: stake, pool: pool, drep: drepKey),
            .registerPool(try CertificateBuildingTests().poolDraft(isUpdate: false)),
            .retirePool(pool: pool, epoch: 300),
            .registerDRep(keyHash: drepKey, anchorURL: "https://example.com/drep.json", anchorHash: anchorHash),
            .unregisterDRep(keyHash: drepKey),
            .updateDRep(keyHash: drepKey, anchorURL: "https://example.com/drep-2.json", anchorHash: anchorHash),
            .authorizeCommitteeHot(coldKey: String(repeating: "12", count: 28), hotKey: String(repeating: "34", count: 28)),
            .resignCommitteeCold(coldKey: String(repeating: "12", count: 28), anchorURL: "", anchorHash: ""),
        ]
        for draft in drafts {
            let original = try #require(try await certificates([draft]).first, "\(draft)")
            // From a text envelope, from CBOR hex, and from raw CBOR.
            let files = [try envelope(original), Data(try original.toCBORData().hex.utf8), try original.toCBORData()]
            for file in files {
                let read = try CertificateFile.draft(from: file, network: .preprod)
                let rebuilt = try #require(try await certificates([read]).first, "\(read)")
                #expect(try rebuilt.toCBORData() == original.toCBORData(), "\(draft) read back as \(read)")
            }
        }
    }

    @Test("A stake registration reads back as the stake address it registers")
    func stakeAddress() throws {
        let stake = try GovernanceBuildingTests.stakeAddress()
        let address = try Address(from: .string(stake))
        guard case .verificationKeyHash(let hash)? = address.stakingPart else { Issue.record("No stake key"); return }
        let certificate = Certificate.register(Register(
            stakeCredential: StakeCredential(credential: .verificationKeyHash(hash)), coin: 2_000_000
        ))
        #expect(try CertificateFile.draft(from: envelope(certificate), network: .preprod) == .registerStake(stakeAddress: stake))
    }

    @Test("A pool registration keeps its margin exactly, as a fraction")
    func poolMargin() async throws {
        var draft = try CertificateBuildingTests().poolDraft(isUpdate: false)
        draft.margin = "1/3"
        let original = try #require(try await certificates([.registerPool(draft)]).first)
        guard case .registerPool(let read) = try CertificateFile.draft(from: envelope(original), network: .preprod) else {
            Issue.record("Not a pool registration")
            return
        }
        #expect(read.margin == "1/3")
        #expect(read.relays.count == draft.relays.count)
        #expect(read.metadataURL == draft.metadataURL)
    }

    @Test("Without a network, a stake credential cannot be shown; what is not a certificate says so")
    func refused() throws {
        let stake = try Address(from: .string(try GovernanceBuildingTests.stakeAddress()))
        guard case .verificationKeyHash(let hash)? = stake.stakingPart else { return }
        let certificate = Certificate.register(Register(stakeCredential: StakeCredential(credential: .verificationKeyHash(hash)), coin: 2_000_000))
        #expect(throws: CertificateFileError.needsNetwork) { try CertificateFile.draft(from: envelope(certificate), network: nil) }
        #expect(throws: CertificateFileError.notACertificate) { try CertificateFile.draft(from: Data("{\"type\":\"Tx\"}".utf8), network: .preprod) }
        #expect(throws: CertificateFileError.notACertificate) { try CertificateFile.draft(from: Data("hello".utf8), network: .preprod) }
        // A pool retirement needs no network.
        let retirement = Certificate.poolRetirement(PoolRetirement(
            poolKeyHash: PoolKeyHash(payload: Data(repeating: 0xAB, count: 28)), epoch: 300
        ))
        #expect(try CertificateFile.draft(from: envelope(retirement), network: nil) == .retirePool(pool: pool, epoch: 300))
    }
}
