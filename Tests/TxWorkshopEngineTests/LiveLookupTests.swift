import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// Runs against public preprod services; set `TW_LIVE=1` to run.
@Suite("Live lookups", .enabled(if: ProcessInfo.processInfo.environment["TW_LIVE"] != nil))
struct LiveLookupTests {
    @Test("Koios resolves the fixture's inputs on preprod")
    func koiosInputs() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let provider = ProviderConfiguration(name: "Koios", kind: .koios, network: .preprod)
        let resolved = try await InputResolver().resolve(transaction: bytes, provider: provider, apiKey: nil)
        print("utxos \(resolved.utxos.count) spent \(resolved.spent) missing \(resolved.missing)")
        #expect(!resolved.utxos.isEmpty)
        let snapshot = ChainContextSnapshot(fetchedAt: .now, utxos: resolved.utxos, spentInputs: resolved.spent)
        let inspection = try await TransactionInspector().inspection(of: bytes, network: .preprod, chainContext: snapshot)
        for input in inspection.inputs {
            print(input.id, input.status, input.output.map { TWFormat.ada($0.lovelace) } ?? "-")
        }
    }

    @Test("Koios lists the open governance actions in one request", arguments: [CardanoNetwork.preprod, .mainnet])
    func koiosOpenActions(_ network: CardanoNetwork) async throws {
        let provider = ProviderConfiguration(name: "Koios", kind: .koios, network: network)
        let window = try await ChainLookup().retirementWindow(provider: provider, apiKey: nil)
        let actions = try await ChainLookup().openGovernanceActions(provider: provider, apiKey: nil)
        print("\(network): epoch \(window.currentEpoch), \(actions.count) open")
        for action in actions { print(" ", action.kind, action.id, action.expiresAfter.map(String.init) ?? "-") }
        #expect(actions.allSatisfy { ($0.expiresAfter ?? .max) >= window.currentEpoch && $0.id.hasPrefix("gov_action1") })
    }

    @Test("Koios gives a stake address's rewards and delegation")
    func koiosAccount() async throws {
        let provider = ProviderConfiguration(name: "Koios", kind: .koios, network: .mainnet)
        // A long-registered mainnet stake address.
        let account = try await ChainLookup().account(
            "stake1u9ylzsgxaa6xctf4juup682ar3juj85n8tx3hthnljg47zctvm3rc", network: .mainnet, provider: provider, apiKey: nil
        )
        print(account)
        #expect(account.isRegistered)
    }

    @Test("The testnet registry answers a batch query")
    func registry() async throws {
        let inspection = try await TransactionInspector().inspection(of: try TransactionInspectionTests.bytes("conway-tx"), network: .preprod)
        let tokens = try await TokenRegistryLookup().lookup(inspection.outputs.flatMap(\.assets) + inspection.mint, network: .preprod)
        print("tokens \(tokens)")
    }

    /// Fetches the fixture's chain data; with `TW_FIXTURE_OUT` set, writes
    /// it there as the offline fixture.
    @Test("Koios gives everything validation needs")
    func chainData() async throws {
        let bytes = try TransactionInspectionTests.bytes("conway-tx")
        let provider = ProviderConfiguration(name: "Koios", kind: .koios, network: .preprod)
        let snapshot = try await ChainDataFetcher().fetch(transaction: bytes, provider: provider, apiKey: nil, keeping: nil)
        #expect(snapshot.protocolParameters != nil)
        #expect(snapshot.utxos.count == 5)
        #expect(snapshot.tipSlot != nil)
        if let out = ProcessInfo.processInfo.environment["TW_FIXTURE_OUT"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: URL(fileURLWithPath: out))
        }
    }
}
