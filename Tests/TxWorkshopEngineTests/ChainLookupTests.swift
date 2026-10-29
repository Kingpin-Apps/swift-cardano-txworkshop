import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import SwiftCardanoTxValidator
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Looking up what the build form is given")
struct ChainLookupTests {
    static let provider = ProviderConfiguration(name: "preprod", kind: .koios, network: .preprod)
    static let keyHash = String(repeating: "ab", count: 28)

    static func stakeAddress() throws -> String {
        try ChainLookup.stakeAddress(keyHash, network: .preprod)
    }

    @Test("The snapshot's epoch gives the next one to retire at, within the protocol's limit")
    func retirementFromSnapshot() throws {
        var snapshot = try TransactionValidationTests.snapshot()
        var ledger = LedgerState.decode(snapshot.ledgerState)
        ledger.currentEpoch = 250
        snapshot.ledgerState = try ledger.encoded()
        let limit = try #require(TransactionValidation.protocolParameters(snapshot)).poolRetireMaxEpoch

        let window = try #require(ChainLookup.retirementWindow(snapshot))
        #expect(window.currentEpoch == 250)
        #expect(window.earliest == 251)
        #expect(window.latest == 250 + UInt64(limit))
        #expect(ChainLookup.retirementWindow(ChainContextSnapshot(fetchedAt: .now, utxos: [])) == nil)
        #expect(ChainLookup.retirementWindow(nil) == nil)
    }

    @Test("The provider's epoch gives the window when there is no snapshot")
    func retirementFromProvider() async throws {
        let lookup = ChainLookup { _, _ in AccountContext(epoch: 90) }
        let window = try await lookup.retirementWindow(provider: Self.provider, apiKey: nil)
        #expect(window.earliest == 91)
        // The stub has no protocol parameters, so no upper limit.
        #expect(window.latest == nil)
    }

    @Test("The provider's account gives the reward balance and delegation")
    func accountFromProvider() async throws {
        let address = try Self.stakeAddress()
        let pool = PoolOperator(poolKeyHash: PoolKeyHash(payload: Data(repeating: 0xcd, count: 28)))
        let lookup = ChainLookup { _, _ in
            AccountContext(infos: [StakeAddressInfo(active: true, address: address, rewardAccountBalance: 4_200_000, stakeDelegation: pool)])
        }
        // A stake key hash is read as its stake address.
        let account = try await lookup.account(Self.keyHash, network: .preprod, provider: Self.provider, apiKey: nil)
        #expect(account == ChainLookup.Account(stakeAddress: address, isRegistered: true, rewards: 4_200_000, pool: pool.description))
    }

    @Test("An address the provider has never seen is unregistered, with no rewards")
    func unknownAccount() async throws {
        let account = try await ChainLookup { _, _ in AccountContext() }
            .account(Self.keyHash, network: .preprod, provider: Self.provider, apiKey: nil)
        #expect(!account.isRegistered && account.rewards == 0)
    }

    @Test("A failing provider and an unreadable address are errors")
    func failures() async throws {
        await #expect(throws: ChainLookupError.self) {
            _ = try await ChainLookup { _, _ in AccountContext(fails: true) }
                .account(Self.keyHash, network: .preprod, provider: Self.provider, apiKey: nil)
        }
        await #expect(throws: ChainLookupError.self) {
            _ = try await ChainLookup { _, _ in AccountContext() }
                .account("not an address", network: .preprod, provider: Self.provider, apiKey: nil)
        }
        await #expect(throws: ChainLookupError.self) {
            _ = try await ChainLookup { _, _ in AccountContext() }
                .governanceAction("nope", provider: Self.provider, apiKey: nil)
        }
    }

    @Test("Open governance actions come back with their CIP-129 ids, kinds and expiry")
    func openActions() async throws {
        let id = GovActionID(transactionID: TransactionId(payload: Data(repeating: 7, count: 32)), govActionIndex: 1)
        let open = OpenGovAction(govActionId: id, type: .treasuryWithdrawalsAction, expiresAfter: 512)
        let actions = try await ChainLookup { _, _ in AccountContext(open: [open]) }.openGovernanceActions(provider: Self.provider, apiKey: nil)
        #expect(actions == [ChainLookup.OpenAction(id: try id.id(), kind: "Treasury withdrawal", expiresAfter: 512, anchorURL: nil)])
        // The id is one the vote form reads back.
        #expect(try TransactionComposer.govActionID(actions[0].id) == id)
    }

    @Test("The snapshot's ledger state answers for the stake addresses it was fetched with")
    func accountFromSnapshot() throws {
        let address = try Self.stakeAddress()
        var ledger = LedgerState()
        ledger.accountContexts = [AccountInputContext(rewardAddress: address, isRegistered: true, balance: Coin(1_500_000))]
        let snapshot = ChainContextSnapshot(fetchedAt: .now, utxos: [], ledgerState: try ledger.encoded())

        let account = try #require(ChainLookup.account(Self.keyHash, network: .preprod, snapshot: snapshot))
        #expect(account.isRegistered && account.rewards == 1_500_000)
        let other = String(repeating: "cd", count: 28)
        #expect(ChainLookup.account(other, network: .preprod, snapshot: snapshot) == nil)
        #expect(ChainLookup.account(Self.keyHash, network: .preprod, snapshot: nil) == nil)
    }
}

/// A chain context that knows some stake addresses and the epoch.
private struct AccountContext: ChainContext {
    var infos: [StakeAddressInfo] = []
    var open: [OpenGovAction] = []
    var epoch = 0
    var fails = false

    var name: String { "stub" }
    var type: ContextType { .online }
    var networkId: NetworkId { .testnet }

    func stakeAddressInfo(address: Address) async throws -> [StakeAddressInfo] {
        if fails { throw CardanoChainError.valueError("offline") }
        return infos
    }

    func openGovActions() async throws -> [OpenGovAction] { open }

    func protocolParameters() async throws -> ProtocolParameters { throw CardanoChainError.notImplemented(nil) }
    func genesisParameters() async throws -> GenesisParameters { throw CardanoChainError.notImplemented(nil) }
    func epoch() async throws -> Int { epoch }
    func era() async throws -> Era? { nil }
    func lastBlockSlot() async throws -> Int { 0 }
}
