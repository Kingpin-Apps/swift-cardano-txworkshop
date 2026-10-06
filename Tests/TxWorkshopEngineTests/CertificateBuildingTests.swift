import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// Every certificate the Conway ledger accepts can be built, balances, and
/// asks for the right signatures.
@Suite("Building every certificate")
struct CertificateBuildingTests {
    let pool = String(repeating: "ab", count: 28)
    let ownerKey = "04619f081850a9c468c25ac4ca72f783b6c3f006cc2dfe4e8a27fdc0"
    let vrf = String(repeating: "cd", count: 32)

    func build(_ certificates: [CertificateDraft]) async throws -> (TransactionComposer.Composition, ProtocolParameters, ChainContextSnapshot) {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], outputs: [OutputDraft(address: address)], changeAddress: address,
            certificates: certificates.map { CertificateItem(certificate: $0) }
        )
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        #expect(built.totalIn == built.totalOut + Int64(built.fee.total) + built.deposits - built.refunds)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        #expect(inspection.view.certificates.count == certificates.count)
        return (built, try #require(TransactionValidation.protocolParameters(snapshot)), snapshot)
    }

    func signers(_ built: TransactionComposer.Composition, _ snapshot: ChainContextSnapshot) throws -> Set<String> {
        Set(try RequiredSignatures.analyze(built.transaction, utxos: snapshot.utxos).signers.map(\.keyHash))
    }

    func poolDraft(isUpdate: Bool) throws -> PoolRegistrationDraft {
        PoolRegistrationDraft(
            pool: pool, vrfKey: vrf, pledge: 500_000_000, cost: 170_000_000, margin: "1%",
            rewardAccount: try GovernanceBuildingTests.stakeAddress(), owners: [ownerKey],
            relays: [RelayDraft(kind: .dnsName, host: "relay.example.com", port: 3001), RelayDraft(kind: .ipv4, host: "203.0.113.7", port: 6000)],
            metadataURL: "https://example.com/pool.json", metadataHash: String(repeating: "11", count: 32), isUpdate: isUpdate
        )
    }

    @Test("A certificate alone builds, with no output: what is left goes back as change")
    func noOutputs() async throws {
        let (snapshot, utxo, address) = try TransactionComposerTests.setup()
        let recipe = BuildRecipe(
            utxos: [try utxo.toCBORData().hex], changeAddress: address,
            certificates: [CertificateItem(certificate: .registerStake(stakeAddress: try GovernanceBuildingTests.stakeAddress()))]
        )
        #expect(RecipeCheck.problems(recipe, network: .preprod).isEmpty)
        let built = try await TransactionComposer().compose(recipe, snapshot: snapshot, network: .preprod)
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        #expect(inspection.outputs.count == 1, "Only the change output.")
        #expect(built.change != nil)
        #expect(inspection.certificates.count == 1)
    }

    @Test("Inspecting a pool registration shows every field Build asked for")
    func poolRegistrationDetail() async throws {
        let (built, _, _) = try await build([.registerPool(try poolDraft(isUpdate: false))])
        let inspection = try await TransactionInspector().inspection(of: built.transaction, network: .preprod)
        let detail = try #require(inspection.certificates.first)
        let fields = Dictionary(detail.fields.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(fields["Pool id"]?.value.hasPrefix("pool1") == true)
        #expect(fields["VRF key hash"]?.value.count == 64)
        #expect(fields["Pledge"]?.kind == .lovelace(500_000_000))
        #expect(fields["Fixed cost per epoch"]?.kind == .lovelace(170_000_000))
        #expect(fields["Margin"]?.value.hasPrefix("1%") == true)
        #expect(fields["Reward account"]?.value.hasPrefix("stake_test1") == true)
        #expect(fields["Owner"]?.value.hasPrefix("stake_test1") == true)
        #expect(fields["Relay 1"]?.value == "relay.example.com:3001")
        #expect(fields["Relay 2"]?.value == "203.0.113.7:6000")
        #expect(fields["Metadata URL"]?.value == "https://example.com/pool.json")
        #expect(fields["Metadata hash"]?.value == String(repeating: "11", count: 32))
    }

    @Test("Combined registration and delegation certificates each pay the stake deposit")
    func combined() async throws {
        let stake = try GovernanceBuildingTests.stakeAddress()
        let (built, parameters, _) = try await build([
            .registerAndDelegateStakeAndVote(stakeAddress: stake, pool: pool, drep: "abstain"),
        ])
        #expect(built.deposits == parameters.stakeAddressDeposit)
        let (others, _, _) = try await build([
            .registerAndDelegateStake(stakeAddress: stake, pool: pool),
            .delegateStakeAndVote(stakeAddress: stake, pool: pool, drep: "no-confidence"),
        ])
        #expect(others.deposits == parameters.stakeAddressDeposit)
        _ = try await build([.registerAndDelegateVote(stakeAddress: stake, drep: "abstain")])
    }

    @Test("Pre-Conway stake registration still builds")
    func legacy() async throws {
        let (built, parameters, _) = try await build([.registerStakeLegacy(stakeAddress: try GovernanceBuildingTests.stakeAddress())])
        #expect(built.deposits == parameters.stakeAddressDeposit)
    }

    @Test("A new pool pays the pool deposit and is signed by its cold key and owners; an update pays nothing")
    func poolRegistration() async throws {
        let (built, parameters, snapshot) = try await build([.registerPool(try poolDraft(isUpdate: false))])
        #expect(built.deposits == parameters.stakePoolDeposit)
        let needed = try signers(built, snapshot)
        #expect(needed.contains(pool))
        #expect(needed.contains(ownerKey))
        let (update, _, _) = try await build([.registerPool(try poolDraft(isUpdate: true))])
        #expect(update.deposits == 0)
    }

    @Test("A pool retires at an epoch, signed by its cold key")
    func retirement() async throws {
        let (built, _, snapshot) = try await build([.retirePool(pool: pool, epoch: 300)])
        #expect(built.deposits == 0 && built.refunds == 0)
        #expect(try signers(built, snapshot).contains(pool))
    }

    @Test("Committee members authorize a hot key and resign")
    func committee() async throws {
        let cold = String(repeating: "12", count: 28)
        let hot = String(repeating: "34", count: 28)
        let (built, _, snapshot) = try await build([
            .authorizeCommitteeHot(coldKey: cold, hotKey: hot),
            .resignCommitteeCold(coldKey: cold, anchorURL: "", anchorHash: ""),
        ])
        #expect(try signers(built, snapshot).contains(cold))
    }

    @Test("A pool registration form is checked field by field")
    func checked() {
        let problems = RecipeCheck.problems(
            BuildRecipe(changeAddress: "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x",
                        certificates: [CertificateItem(certificate: .registerPool(PoolRegistrationDraft(margin: "150%")))]),
            network: .preprod
        ).map(\.field)
        for field in ["Pool", "VRF key", "Pledge", "Fixed cost", "Margin", "Reward account", "Owners"] {
            #expect(problems.contains(field), "\(field) not checked")
        }
    }

    @Test("Margins read as decimals, percentages and fractions")
    func margins() {
        #expect(PoolMargin.parse("0.05") == UnitInterval(numerator: 1, denominator: 20))
        #expect(PoolMargin.parse("5%") == UnitInterval(numerator: 1, denominator: 20))
        #expect(PoolMargin.parse("1/20") == UnitInterval(numerator: 1, denominator: 20))
        #expect(PoolMargin.parse("0") == UnitInterval(numerator: 0, denominator: 1))
        #expect(PoolMargin.parse("1.5") == nil)
        #expect(PoolMargin.parse("abc") == nil)
        #expect(PoolMargin.text(UnitInterval(numerator: 1, denominator: 20)) == "0.05")
    }

    @Test("An scm pool.json fills the form; key files it can't reach are noted")
    func poolJSON() throws {
        let json = """
        {"name": "mypool", "id_bech": "\(try PoolOperator(poolKeyHash: PoolKeyHash(payload: Data(repeating: 0xAB, count: 28))).toBech32())",
         "vrf_key_hash": "\(vrf)", "pledge": 100000000000, "cost": 170000000, "margin": 0.05,
         "owners": [{"name": "owner1", "stake_key_hash": "\(ownerKey)"}, {"name": "owner2", "stake_vkey": "missing.stake.vkey"}],
         "rewards_owner": {"name": "owner1", "stake_key_hash": "\(ownerKey)"},
         "relays": [{"type": "dns", "host": "relay1.example.com", "port": 3001, "host_type": "single"},
                    {"type": "ip", "host": "203.0.113.7", "port": 6000, "host_type": "ipv4"},
                    {"type": "dns", "host": "_cardano._tcp.example.com", "host_type": "multi"}],
         "meta_url": "https://example.com/p.json", "metadata_hash": "\(String(repeating: "11", count: 32))"}
        """
        let imported = try PoolRegistrationSource.poolJSON(Data(json.utf8), folder: nil)
        let draft = imported.draft
        #expect(draft.pool.hasPrefix("pool1"))
        #expect(draft.vrfKey == vrf)
        #expect(draft.pledge == 100_000_000_000 && draft.cost == 170_000_000)
        #expect(PoolMargin.parse(draft.margin) == UnitInterval(numerator: 1, denominator: 20))
        #expect(draft.owners == [ownerKey])
        #expect(draft.rewardAccount == ownerKey)
        #expect(draft.relays.map(\.kind) == [.dnsName, .ipv4, .srvName])
        #expect(draft.relays[2].port == nil)
        #expect(draft.metadataURL == "https://example.com/p.json")
        #expect(imported.notes.count == 2)  // owner2's stake key file, and owner2 itself
        #expect(!draft.isUpdate)
    }

    @Test("Registered pool parameters come back as an editable update")
    func fromChain() throws {
        try ValueReader.$buildNetwork.withValue(.preprod) {
            let params = try TransactionComposer.poolParams(try poolDraft(isUpdate: false))
            let draft = try PoolRegistrationSource.draft(params, isUpdate: true)
            #expect(draft.isUpdate)
            #expect(try TransactionComposer.poolParams(draft) == params)
        }
    }
}
