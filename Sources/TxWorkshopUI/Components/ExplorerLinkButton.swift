import SwiftCardanoCore
import SwiftCardanoExplorers
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

extension BlockchainExplorer {
    /// Where the chosen explorer is kept.
    public static let storageKey = "blockchainExplorer"

    /// The explorer to open `item` in on `network`: the chosen one when it
    /// has the page, or else the first that does, full explorers first.
    static func opening(_ item: ExplorerItem, on network: Network, preferring chosen: BlockchainExplorer) -> (BlockchainExplorer, URL)? {
        let fallbacks: [BlockchainExplorer] = [.cardanoScan, .cexplorer, .adaStat, .poolPM, .drepTalk, .poolTool, .eutxo]
        for explorer in [chosen] + fallbacks {
            if let url = explorer.link(for: item, on: network) { return (explorer, url) }
        }
        return nil
    }
}

/// Opens an item in the chosen block explorer, on the document's network.
/// Shows nothing when no explorer has a page for it there, or the network is
/// unknown.
struct ExplorerLinkButton: View {
    let item: ExplorerItem?
    @Environment(\.documentNetwork) private var network
    @AppStorage(BlockchainExplorer.storageKey) private var chosen = BlockchainExplorer.cexplorer

    var body: some View {
        if let item, let network, case let (explorer, url)? = BlockchainExplorer.opening(item, on: network.cardanoCoreNetwork, preferring: chosen) {
            Link(destination: url) {
                Label {
                    Text("Open in \(explorer.name)", bundle: #bundle)
                } icon: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .labelStyle(.iconOnly)
                .twHitTarget()
            }
            .buttonStyle(.borderless)
            .help(Text("Open in \(explorer.name)", bundle: #bundle))
        }
    }
}

/// Explorer items from the text the inspection shows.
extension ExplorerItem {
    /// A transaction by its id, or by an input's `id#index`.
    static func transaction(_ text: String) -> ExplorerItem? {
        let hex = text.split(separator: "#").first.map(String.init) ?? text
        guard hex.count == 64, let bytes = Data(hexString: hex) else { return nil }
        return .transaction(TransactionId(payload: bytes))
    }

    /// An address in bech32 or hex.
    static func address(_ text: String) -> ExplorerItem? {
        (try? Address(from: .string(text))).map { .address($0) }
    }

    /// The stake account of an address, or of a stake address.
    static func account(_ text: String) -> ExplorerItem? {
        guard let address = try? Address(from: .string(text)), address.stakingPart != nil else { return nil }
        return .account(address)
    }

    /// A stake credential shown as `key:<hex>` or `script:<hex>`, as a stake
    /// account on `network`.
    static func account(credential text: String, network: CardanoNetwork?) -> ExplorerItem? {
        guard let network, let (isScript, bytes) = credential(text) else { return nil }
        let part: StakingPart = isScript ? .scriptHash(ScriptHash(payload: bytes)) : .verificationKeyHash(VerificationKeyHash(payload: bytes))
        return (try? Address(stakingPart: part, network: network == .mainnet ? .mainnet : .testnet)).map { .account($0) }
    }

    /// A pool by its hex id or `pool1…`.
    static func pool(_ text: String) -> ExplorerItem? {
        if let pool = try? PoolOperator(from: text) { return .pool(pool) }
        guard text.count == 56, let bytes = Data(hexString: text) else { return nil }
        return .pool(PoolOperator(poolKeyHash: PoolKeyHash(payload: bytes)))
    }

    /// A DRep by its id; nil for abstain and no confidence.
    static func drep(_ text: String) -> ExplorerItem? {
        (try? DRep(from: text)).map { .drep($0) }
    }

    /// A voter shown by role and `key:<hex>` or `script:<hex>`: a DRep's or a
    /// pool's page. Committee members vote with hot keys, which have none.
    static func voter(role: String, credential text: String) -> ExplorerItem? {
        guard let (isScript, bytes) = credential(text) else { return nil }
        switch role {
        case "drep":
            let credential: DRepType = isScript ? .scriptHash(ScriptHash(payload: bytes)) : .verificationKeyHash(VerificationKeyHash(payload: bytes))
            return .drep(DRep(credential: credential))
        case "spo" where !isScript:
            return .pool(PoolOperator(poolKeyHash: PoolKeyHash(payload: bytes)))
        default:
            return nil
        }
    }

    /// A governance action as `txhash#index` or `gov_action1…`.
    static func governanceAction(_ text: String) -> ExplorerItem? {
        if let id = try? GovActionID(from: text) { return .governanceAction(id) }
        let parts = text.split(separator: "#")
        guard parts.count == 2, parts[0].count == 64, let bytes = Data(hexString: String(parts[0])), let index = UInt16(parts[1]) else {
            return nil
        }
        return .governanceAction(GovActionID(transactionID: TransactionId(payload: bytes), govActionIndex: index))
    }

    static func policy(_ hex: String) -> ExplorerItem? {
        guard hex.count == 56, let bytes = Data(hexString: hex) else { return nil }
        return .policy(PolicyID(payload: bytes))
    }

    static func asset(policy hex: String, name nameHex: String) -> ExplorerItem? {
        guard hex.count == 56, let policy = Data(hexString: hex), let name = try? AssetName(payload: Data(hexString: nameHex) ?? Data()) else {
            return nil
        }
        return .asset(policy: PolicyID(payload: policy), name: name)
    }

    private static func credential(_ text: String) -> (isScript: Bool, bytes: Data)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[1].count == 56, let bytes = Data(hexString: String(parts[1])) else { return nil }
        return (parts[0] == "script", bytes)
    }
}
