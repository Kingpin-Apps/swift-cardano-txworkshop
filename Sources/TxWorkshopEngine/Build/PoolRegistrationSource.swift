import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import TxWorkshopCore

/// Fills a pool registration form: from an `scm` or cardano-cli style
/// `pool.json`, or from the pool's registration on chain.
public enum PoolRegistrationSource {
    /// A draft read from a pool.json, with notes on anything it named but
    /// could not read (key files outside the app's reach, for example).
    public struct Imported: Sendable, Equatable {
        public let draft: PoolRegistrationDraft
        public let notes: [String]
    }

    /// Reads a pool.json. Key file paths in it are read from `folder` (the
    /// file's own folder) when they can be; hashes stored in the file are used
    /// when they can't.
    public static func poolJSON(_ data: Data, folder: URL?) throws -> Imported {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValueReadError("That is not a pool.json: it isn't a JSON object.")
        }
        var notes: [String] = []
        func string(_ key: String, in object: [String: Any] = json) -> String? {
            (object[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        func number(_ key: String) -> UInt64? {
            if let number = json[key] as? NSNumber { return number.uint64Value }
            return string(key).flatMap(UInt64.init)
        }
        /// The text of a key file the JSON points to, if it can be read.
        func file(_ key: String, in object: [String: Any] = json, what: String) -> String? {
            guard let path = string(key, in: object) else { return nil }
            let url = path.hasPrefix("/") || path.hasPrefix("~")
                ? URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                : folder.map { $0.appendingPathComponent(path) } ?? URL(fileURLWithPath: path)
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
            notes.append("The \(what) file \(path) couldn't be read here; choose it in the form.")
            return nil
        }

        var draft = PoolRegistrationDraft()
        draft.pool = string("id_bech") ?? string("id_hex") ?? file("cold_vkey", what: "cold key") ?? ""
        draft.vrfKey = string("vrf_key_hash") ?? file("vrf_vkey", what: "VRF key") ?? ""
        draft.pledge = number("pledge")
        draft.cost = number("cost")
        if let margin = json["margin"] as? NSNumber {
            draft.margin = "\(margin.decimalValue)"
        } else {
            draft.margin = string("margin") ?? ""
        }

        for owner in json["owners"] as? [[String: Any]] ?? [] {
            if let hash = string("stake_key_hash", in: owner) {
                draft.owners.append(hash)
            } else if let key = file("stake_vkey", in: owner, what: "owner's stake key") {
                draft.owners.append(key)
            } else {
                notes.append("An owner (\(string("name", in: owner) ?? "unnamed")) has no stake key hash or readable stake key.")
            }
        }
        if let rewards = json["rewards_owner"] as? [String: Any] {
            draft.rewardAccount = string("reward_account", in: rewards)
                ?? string("stake_key_hash", in: rewards)
                ?? file("stake_vkey", in: rewards, what: "rewards owner's stake key") ?? ""
        }

        for relay in json["relays"] as? [[String: Any]] ?? [] {
            let host = string("host", in: relay) ?? ""
            let port = (relay["port"] as? NSNumber).map { UInt16(truncatingIfNeeded: $0.intValue) }
                ?? string("port", in: relay).flatMap(UInt16.init)
            let kind: RelayDraft.Kind = switch (string("type", in: relay), string("host_type", in: relay)) {
            case (_, "ipv6"?): .ipv6
            case (_, "multi"?): .srvName
            case ("ip"?, _), (_, "ipv4"?): .ipv4
            default: .dnsName
            }
            draft.relays.append(RelayDraft(kind: kind, host: host, port: kind == .srvName ? nil : port))
        }
        draft.metadataURL = string("meta_url") ?? ""
        draft.metadataHash = string("metadata_hash") ?? ""
        // A pool.json with a registration on record is for a pool already on chain.
        draft.isUpdate = json["registration"] != nil
        return Imported(draft: draft, notes: notes)
    }

    /// The pool's parameters as registered on chain, ready to edit and
    /// register again as an update; `nil` when the provider doesn't know the
    /// pool.
    public static func registered(
        _ pool: String, provider: ProviderConfiguration, apiKey: String?, network: CardanoNetwork?
    ) async throws -> PoolRegistrationDraft? {
        let id = try ValueReader.read(.pool, text: pool, network: network).value
        let context = try await ChainContextFactory().makeContext(for: provider, apiKey: apiKey)
        let info: StakePoolInfo
        do {
            info = try await context.stakePoolInfo(poolId: id)
        } catch {
            return nil
        }
        return try draft(info.poolParams, isUpdate: true)
    }

    /// A form draft for `params`.
    static func draft(_ params: PoolParams, isUpdate: Bool) throws -> PoolRegistrationDraft {
        let reward = try Address(from: .bytes(params.rewardAccount.payload)).toBech32()
        return PoolRegistrationDraft(
            pool: try PoolOperator(poolKeyHash: params.poolOperator).toBech32(),
            vrfKey: params.vrfKeyHash.payload.hex,
            pledge: UInt64(params.pledge),
            cost: UInt64(params.cost),
            margin: PoolMargin.text(params.margin),
            rewardAccount: reward,
            owners: params.poolOwners.asArray.map(\.payload.hex),
            relays: (params.relays ?? []).map(relay),
            metadataURL: params.poolMetadata?.url?.absoluteString ?? "",
            metadataHash: params.poolMetadata?.poolMetadataHash?.payload.hex ?? "",
            isUpdate: isUpdate
        )
    }

    static func relay(_ relay: Relay) -> RelayDraft {
        switch relay {
        case .singleHostAddr(let address):
            if let ipv4 = address.ipv4 {
                return RelayDraft(kind: .ipv4, host: ipv4.description, port: address.port.map { UInt16(truncatingIfNeeded: $0) })
            }
            return RelayDraft(kind: .ipv6, host: address.ipv6?.description ?? "", port: address.port.map { UInt16(truncatingIfNeeded: $0) })
        case .singleHostName(let name):
            return RelayDraft(kind: .dnsName, host: name.dnsName ?? "", port: name.port.map { UInt16(truncatingIfNeeded: $0) })
        case .multiHostName(let name):
            return RelayDraft(kind: .srvName, host: name.dnsName ?? "", port: nil)
        }
    }
}
