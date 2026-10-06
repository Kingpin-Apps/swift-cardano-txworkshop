import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// One certificate, field by field: everything Build asks for when making it.
public struct CertificateDetail: Sendable, Equatable, Identifiable {
    /// 1-based, as the certificate list counts them.
    public let index: Int
    public let fields: [Field]
    public var id: Int { index }

    public struct Field: Sendable, Equatable, Identifiable {
        public let id: Int
        public let label: String
        public let value: String
        public let kind: Kind
    }

    /// How a field's value reads, and where it links.
    public enum Kind: Sendable, Equatable {
        case text
        /// Hex or bech32, shown in the bytes font.
        case identifier
        case lovelace(Int64)
        case pool
        case stakeAddress
        case drep
        case url
    }
}

extension CertificateDetail {
    /// The fields of `certificate`, the `index`-th (1-based). Credentials read
    /// as stake addresses on `network` when it is known.
    static func of(_ certificate: Certificate, index: Int, network: CardanoNetwork?) -> CertificateDetail {
        var fields: [Field] = []
        func add(_ label: String, _ value: String, _ kind: Kind = .identifier) {
            fields.append(Field(id: fields.count, label: label, value: value, kind: kind))
        }
        func stake(_ credential: CredentialType, _ label: String = "Stake credential") {
            if let network, let address = try? Address(paymentPart: nil, stakingPart: stakingPart(credential), network: network == .mainnet ? .mainnet : .testnet),
                let bech32 = try? address.toBech32() {
                add("Stake address", bech32, .stakeAddress)
            }
            add(label, Self.describe(credential))
        }
        func pool(_ hash: PoolKeyHash, _ label: String = "Pool") {
            add(label, (try? PoolOperator(poolKeyHash: hash).toBech32()) ?? hash.payload.hex, .pool)
        }
        func drep(_ drep: DRep) {
            switch drep.credential {
            case .alwaysAbstain: add("DRep", "Always abstain", .text)
            case .alwaysNoConfidence: add("DRep", "Always no confidence", .text)
            default: add("DRep", (try? drep.toBech32()) ?? "\(drep.credential)", .drep)
            }
        }
        func coin(_ label: String, _ coin: Coin) { add(label, TWFormat.ada(Int64(coin)), .lovelace(Int64(coin))) }
        func anchor(_ anchor: Anchor?) {
            guard let anchor else { return }
            add("Anchor URL", anchor.anchorUrl.absoluteString, .url)
            add("Anchor hash", anchor.anchorDataHash.payload.hex)
        }

        switch certificate {
        case .stakeRegistration(let c): stake(c.stakeCredential.credential)
        case .stakeDeregistration(let c): stake(c.stakeCredential.credential)
        case .stakeDelegation(let c):
            stake(c.stakeCredential.credential)
            pool(c.poolKeyHash)
        case .register(let c):
            stake(c.stakeCredential.credential)
            coin("Deposit", c.coin)
        case .unregister(let c):
            stake(c.stakeCredential.credential)
            coin("Refund", c.coin)
        case .voteDelegate(let c):
            stake(c.stakeCredential.credential)
            drep(c.drep)
        case .stakeVoteDelegate(let c):
            stake(c.stakeCredential.credential)
            pool(c.poolKeyHash)
            drep(c.drep)
        case .stakeRegisterDelegate(let c):
            stake(c.stakeCredential.credential)
            pool(c.poolKeyHash)
            coin("Deposit", c.coin)
        case .voteRegisterDelegate(let c):
            stake(c.stakeCredential.credential)
            drep(c.drep)
            coin("Deposit", c.coin)
        case .stakeVoteRegisterDelegate(let c):
            stake(c.stakeCredential.credential)
            pool(c.poolKeyHash)
            drep(c.drep)
            coin("Deposit", c.coin)
        case .poolRegistration(let c):
            let params = c.poolParams
            pool(params.poolOperator, "Pool id")
            add("Cold key hash", params.poolOperator.payload.hex)
            add("VRF key hash", params.vrfKeyHash.payload.hex)
            coin("Pledge", Coin(params.pledge))
            coin("Fixed cost per epoch", Coin(params.cost))
            add("Margin", Self.percent(params.margin), .text)
            Self.rewardAccount(params.rewardAccount.payload, network: network).map { add("Reward account", $0, .stakeAddress) }
            for (number, owner) in params.poolOwners.asArray.enumerated() {
                let label = params.poolOwners.asArray.count == 1 ? "Owner" : "Owner \(number + 1)"
                if let network, let address = try? Address(paymentPart: nil, stakingPart: .verificationKeyHash(owner), network: network == .mainnet ? .mainnet : .testnet),
                    let bech32 = try? address.toBech32() {
                    add(label, bech32, .stakeAddress)
                } else {
                    add(label, owner.payload.hex)
                }
            }
            for (number, relay) in (params.relays ?? []).enumerated() {
                add("Relay \(number + 1)", Self.describe(relay), .text)
            }
            if let metadata = params.poolMetadata {
                if let url = metadata.url { add("Metadata URL", url.absoluteString, .url) }
                if let hash = metadata.poolMetadataHash { add("Metadata hash", hash.payload.hex) }
            }
        case .poolRetirement(let c):
            pool(c.poolKeyHash)
            add("Retirement epoch", "\(c.epoch)", .text)
        case .registerDRep(let c):
            add("DRep", Self.describe(c.drepCredential.credential))
            coin("Deposit", c.coin)
            anchor(c.anchor)
        case .unRegisterDRep(let c):
            add("DRep", Self.describe(c.drepCredential.credential))
            coin("Refund", c.coin)
        case .updateDRep(let c):
            add("DRep", Self.describe(c.drepCredential.credential))
            anchor(c.anchor)
        case .authCommitteeHot(let c):
            add("Cold credential", Self.describe(c.committeeColdCredential.credential))
            add("Hot credential", Self.describe(c.committeeHotCredential.credential))
        case .resignCommitteeCold(let c):
            add("Cold credential", Self.describe(c.committeeColdCredential.credential))
            anchor(c.anchor)
        case .genesisKeyDelegation, .moveInstantaneousRewards:
            add("Contents", (try? certificate.toCBORHex()) ?? "", .identifier)
        }
        return CertificateDetail(index: index, fields: fields)
    }

    static func stakingPart(_ credential: CredentialType) -> StakingPart {
        switch credential {
        case .verificationKeyHash(let hash): .verificationKeyHash(hash)
        case .scriptHash(let hash): .scriptHash(hash)
        }
    }

    static func describe(_ credential: CredentialType) -> String {
        switch credential {
        case .verificationKeyHash(let hash): "key:\(hash.payload.hex)"
        case .scriptHash(let hash): "script:\(hash.payload.hex)"
        }
    }

    static func describe(_ relay: Relay) -> String {
        switch relay {
        case .singleHostAddr(let r):
            let host = [r.ipv4?.description, r.ipv6?.description].compactMap { $0 }.joined(separator: ", ")
            return r.port.map { "\(host):\($0)" } ?? host
        case .singleHostName(let r):
            let host = r.dnsName ?? ""
            return r.port.map { "\(host):\($0)" } ?? host
        case .multiHostName(let r):
            return "\(r.dnsName ?? "") (DNS SRV)"
        }
    }

    static func percent(_ margin: UnitInterval) -> String {
        guard margin.denominator > 0 else { return "\(margin.numerator)/\(margin.denominator)" }
        let value = Double(margin.numerator) / Double(margin.denominator) * 100
        return "\(value.formatted(.number.precision(.fractionLength(0...4))))% (\(margin.numerator)/\(margin.denominator))"
    }

    /// A reward account's bytes (header and credential) as a stake address.
    static func rewardAccount(_ bytes: Data, network: CardanoNetwork?) -> String? {
        if let address = try? Address(from: .bytes(bytes)), let bech32 = try? address.toBech32() { return bech32 }
        return bytes.hex
    }
}
