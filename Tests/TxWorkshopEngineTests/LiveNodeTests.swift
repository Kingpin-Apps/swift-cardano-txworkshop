#if os(macOS)
import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// Runs both node providers against a synced mainnet node. Set
/// `TW_NODE_SOCKET` to its socket, and `TW_CARDANO_CLI` to cardano-cli when
/// it is not in one of the usual places. Nothing is submitted.
@Suite("Live mainnet node", .enabled(if: ProcessInfo.processInfo.environment["TW_NODE_SOCKET"] != nil))
struct LiveNodeTests {
    /// An address with several multi-asset UTxOs, from a real transaction.
    static let address = "addr1qx7a3e0cmwrdspnslsy5hc602w7zvx5ejw924avw8them8mj5qpt4teewa586j20qh6fqdt47xns85ta22hkr32twatq3ym80g"
    /// Inputs of that transaction, since spent.
    static let spentInputs = [
        "01e9d18aeff8432b38d0b7b79faf813ec214cffe3ccd601983a9ed5dc119458c#0",
        "01e9d18aeff8432b38d0b7b79faf813ec214cffe3ccd601983a9ed5dc119458c#1",
    ]

    let socket = ProcessInfo.processInfo.environment["TW_NODE_SOCKET"] ?? ""
    let cli = ProcessInfo.processInfo.environment["TW_CARDANO_CLI"]

    var providers: [ProviderConfiguration] {
        [
            ProviderConfiguration(name: "Node", kind: .localNode, network: .mainnet, socketPath: socket),
            ProviderConfiguration(name: "CLI", kind: .cardanoCLI, network: .mainnet, socketPath: socket, cliPath: cli),
        ]
    }

    func context(_ provider: ProviderConfiguration) async throws -> any ChainContext {
        try await ChainContextFactory().makeContext(for: provider, apiKey: nil)
    }

    @Test("Both providers agree on the tip, the parameters and an address's UTxOs")
    func agree() async throws {
        var slots: [Int] = []
        var feeParameters: [String] = []
        var utxoSets: [Set<String>] = []
        for provider in providers {
            let context = try await context(provider)
            let slot = try await context.lastBlockSlot()
            let epoch = try await context.epoch()
            let era = try await context.era()
            let parameters = try await context.protocolParameters()
            let genesis = try await context.genesisParameters()
            let utxos = try await context.utxos(address: try Address(from: .string(Self.address)))
            let assets = utxos.reduce(0) { $0 + ($1.output.amount.multiAsset.count) }
            print("\(provider.kind): slot \(slot) epoch \(epoch) era \(era.map { "\($0)" } ?? "-") minFeeA \(parameters.txFeePerByte) minFeeB \(parameters.txFeeFixed) maxTx \(parameters.maxTxSize) slotLength \(genesis.slotLength.map { "\($0)" } ?? "-") utxos \(utxos.count) policies \(assets)")
            slots.append(slot)
            feeParameters.append("\(parameters.txFeePerByte) \(parameters.txFeeFixed) \(parameters.maxTxSize) \(parameters.utxoCostPerByte)")
            utxoSets.append(Set(utxos.map { "\($0.input.description) \($0.output.amount.coin)" }))
            #expect(era == .conway)
            #expect(!utxos.isEmpty)
        }
        #expect(abs(slots[0] - slots[1]) < 120)
        #expect(feeParameters[0] == feeParameters[1])
        #expect(utxoSets[0] == utxoSets[1])
    }

    @Test("A spent input is found spent, or missing, through both")
    func spentInputs() async throws {
        for provider in providers {
            let context = try await context(provider)
            for input in Self.spentInputs {
                let found = try await context.utxo(input: try TransactionInput(from: input))
                print("\(provider.kind): \(input) → \(found.map { "found, spent \($0.isSpent)" } ?? "not in the UTxO set")")
                #expect(found == nil || found?.isSpent == true)
            }
        }
    }

    @Test("A payment from the address composes through both, unsigned and not submitted")
    func compose() async throws {
        let recipe = BuildRecipe(
            sourceAddresses: [Self.address],
            outputs: [OutputDraft(address: Self.address, lovelace: 5_000_000)],
            changeAddress: Self.address
        )
        var fees: [Int64] = []
        for provider in providers {
            let composition = try await TransactionComposer().compose(recipe, snapshot: nil, network: .mainnet, provider: provider)
            print("\(provider.kind): \(composition.id) fee \(composition.fee.total) inputs \(composition.inputs.count) in \(composition.totalIn) out \(composition.totalOut)")
            let fee = Int64(composition.fee.total)
            let spent: Int64 = composition.totalOut + fee + composition.deposits - composition.refunds
            #expect(composition.totalIn == spent)
            fees.append(fee)
        }
        #expect(fees.allSatisfy { $0 > 150_000 && $0 < 500_000 })
    }
}
#endif
