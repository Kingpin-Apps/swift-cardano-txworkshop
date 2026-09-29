import Foundation
import SwiftCardanoCore
import SwiftCardanoExplorers
import Testing
import TxWorkshopCore

@testable import TxWorkshopUI

@Suite("Explorer links from the inspection's text")
struct ExplorerLinkTests {
    static let tx = "01e9d18aeff8432b38d0b7b79faf813ec214cffe3ccd601983a9ed5dc119458c"
    static let address = "addr1qx7a3e0cmwrdspnslsy5hc602w7zvx5ejw924avw8them8mj5qpt4teewa586j20qh6fqdt47xns85ta22hkr32twatq3ym80g"
    static let stakeHash = "72a002baaf3977687d494f05f4903575f1a703d17d52af61c54b7756"
    static let poolHex = "d9812f8d30b5db4b03e5b76cfd242db9cd2763da4671ed062be808a0"

    func url(_ item: ExplorerItem?, _ explorer: BlockchainExplorer = .cexplorer, on network: Network = .mainnet) -> String? {
        guard let item else { return nil }
        return BlockchainExplorer.opening(item, on: network, preferring: explorer)?.1.absoluteString
    }

    @Test("Transactions, inputs, addresses and stake accounts")
    func basics() {
        #expect(url(ExplorerItem.transaction(Self.tx)) == "https://cexplorer.io/tx/\(Self.tx)")
        #expect(url(ExplorerItem.transaction("\(Self.tx)#1")) == "https://cexplorer.io/tx/\(Self.tx)")
        #expect(url(ExplorerItem.address(Self.address)) == "https://cexplorer.io/address/\(Self.address)")
        #expect(url(ExplorerItem.account(Self.address), .adaStat) == "https://adastat.net/accounts/\(Self.stakeHash)")
        #expect(url(ExplorerItem.account(credential: "key:\(Self.stakeHash)", network: .mainnet), .poolTool)
            == "https://pooltool.io/address/\(Self.stakeHash)")
        #expect(ExplorerItem.transaction("not hex") == nil)
    }

    @Test("Pools, voters and governance actions")
    func governance() {
        #expect(url(ExplorerItem.pool(Self.poolHex), .poolTool) == "https://pooltool.io/pool/\(Self.poolHex)")
        #expect(url(ExplorerItem.voter(role: "spo", credential: "key:\(Self.poolHex)"), .poolTool) == "https://pooltool.io/pool/\(Self.poolHex)")
        #expect(ExplorerItem.voter(role: "committee", credential: "key:\(Self.poolHex)") == nil)
        #expect(url(ExplorerItem.voter(role: "drep", credential: "key:\(Self.poolHex)"))?.hasPrefix("https://cexplorer.io/drep/drep1") == true)
        #expect(url(ExplorerItem.governanceAction("\(Self.tx)#2"), .adaStat) == "https://adastat.net/governances/\(Self.tx)02")
        #expect(ExplorerItem.drep("abstain") == nil)
    }

    @Test("The chosen explorer, or the first that has the page")
    func fallback() throws {
        let tx = try #require(ExplorerItem.transaction(Self.tx))
        // PoolTool has no transaction pages, and AdaStat no preprod site.
        #expect(BlockchainExplorer.opening(tx, on: .mainnet, preferring: .poolTool)?.0 == .cardanoScan)
        #expect(BlockchainExplorer.opening(tx, on: .preprod, preferring: .adaStat)?.0 == .cardanoScan)
        #expect(BlockchainExplorer.opening(tx, on: .preview, preferring: .cexplorer)?.0 == .cexplorer)
        #expect(BlockchainExplorer.opening(tx, on: .sanchonet, preferring: .cexplorer) == nil)
    }
}
