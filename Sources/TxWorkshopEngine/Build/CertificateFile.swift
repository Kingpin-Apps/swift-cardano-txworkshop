import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// A certificate read from a file: a cardano-cli text envelope (`.cert`,
/// `.json`), its CBOR as hex, or the raw CBOR, as the draft the Build form
/// edits, so it is checked, priced and signed for like one entered by hand.
public enum CertificateFile {
    /// The certificate `data` holds, as a draft. Stake credentials become
    /// stake addresses on `network`; a pool registration's owners take the
    /// network of its reward account.
    public static func draft(from data: Data, network: CardanoNetwork?) throws -> CertificateDraft {
        let certificate: Certificate
        do {
            certificate = try Certificate.fromCBOR(data: try cbor(in: data))
        } catch let error as CertificateFileError {
            throw error
        } catch {
            throw CertificateFileError.notACertificate
        }
        return try draft(certificate, network: network)
    }

    /// The certificate's CBOR: from a text envelope's `cborHex`, from hex, or
    /// the bytes themselves.
    static func cbor(in data: Data) throws -> Data {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("{") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                let hex = object["cborHex"] as? String, let bytes = try? TxDocumentCodec.bytes(fromHex: hex)
            else { throw CertificateFileError.notACertificate }
            return bytes
        }
        if let bytes = try? TxDocumentCodec.bytes(fromHex: text), !bytes.isEmpty { return bytes }
        return data
    }

    static func draft(_ certificate: Certificate, network: CardanoNetwork?) throws -> CertificateDraft {
        func stake(_ credential: StakeCredential) throws -> String {
            guard let network else { throw CertificateFileError.needsNetwork }
            return try stakeAddress(credential.credential, network: network.networkId)
        }
        switch certificate {
        case .register(let c): return .registerStake(stakeAddress: try stake(c.stakeCredential))
        case .unregister(let c): return .deregisterStake(stakeAddress: try stake(c.stakeCredential))
        case .stakeRegistration(let c): return .registerStakeLegacy(stakeAddress: try stake(c.stakeCredential))
        case .stakeDeregistration(let c): return .deregisterStakeLegacy(stakeAddress: try stake(c.stakeCredential))
        case .stakeDelegation(let c): return .delegateStake(stakeAddress: try stake(c.stakeCredential), pool: c.poolKeyHash.payload.hex)
        case .voteDelegate(let c): return .delegateVote(stakeAddress: try stake(c.stakeCredential), drep: try drep(c.drep))
        case .stakeVoteDelegate(let c):
            return .delegateStakeAndVote(stakeAddress: try stake(c.stakeCredential), pool: c.poolKeyHash.payload.hex, drep: try drep(c.drep))
        case .stakeRegisterDelegate(let c):
            return .registerAndDelegateStake(stakeAddress: try stake(c.stakeCredential), pool: c.poolKeyHash.payload.hex)
        case .voteRegisterDelegate(let c):
            return .registerAndDelegateVote(stakeAddress: try stake(c.stakeCredential), drep: try drep(c.drep))
        case .stakeVoteRegisterDelegate(let c):
            return .registerAndDelegateStakeAndVote(
                stakeAddress: try stake(c.stakeCredential), pool: c.poolKeyHash.payload.hex, drep: try drep(c.drep)
            )
        case .poolRegistration(let c):
            return .registerPool(try pool(c.poolParams))
        case .poolRetirement(let c):
            return .retirePool(pool: c.poolKeyHash.payload.hex, epoch: UInt64(c.epoch))
        case .registerDRep(let c):
            let (url, hash) = anchor(c.anchor)
            return .registerDRep(keyHash: try keyHash(c.drepCredential.credential, "A DRep"), anchorURL: url, anchorHash: hash)
        case .unRegisterDRep(let c):
            return .unregisterDRep(keyHash: try keyHash(c.drepCredential.credential, "A DRep"))
        case .updateDRep(let c):
            let (url, hash) = anchor(c.anchor)
            return .updateDRep(keyHash: try keyHash(c.drepCredential.credential, "A DRep"), anchorURL: url, anchorHash: hash)
        case .authCommitteeHot(let c):
            return .authorizeCommitteeHot(
                coldKey: try keyHash(c.committeeColdCredential.credential, "A committee cold credential"),
                hotKey: try keyHash(c.committeeHotCredential.credential, "A committee hot credential")
            )
        case .resignCommitteeCold(let c):
            let (url, hash) = anchor(c.anchor)
            return .resignCommitteeCold(
                coldKey: try keyHash(c.committeeColdCredential.credential, "A committee cold credential"), anchorURL: url, anchorHash: hash
            )
        case .genesisKeyDelegation, .moveInstantaneousRewards:
            throw CertificateFileError.unsupported("Genesis key delegation and instantaneous rewards were removed in Conway.")
        }
    }

    static func stakeAddress(_ credential: CredentialType, network: NetworkId) throws -> String {
        let part: StakingPart = switch credential {
        case .verificationKeyHash(let hash): .verificationKeyHash(hash)
        case .scriptHash(let hash): .scriptHash(hash)
        }
        return try Address(stakingPart: part, network: network).toBech32()
    }

    /// A key credential's hash, as hex; the form takes no script credential here.
    static func keyHash(_ credential: CredentialType, _ what: String) throws -> String {
        guard case .verificationKeyHash(let hash) = credential else {
            throw CertificateFileError.unsupported("\(what) that is a script cannot be entered in the form.")
        }
        return hash.payload.hex
    }

    static func drep(_ drep: DRep) throws -> String {
        switch drep.credential {
        case .alwaysAbstain: return "abstain"
        case .alwaysNoConfidence: return "no-confidence"
        case .verificationKeyHash(let hash): return hash.payload.hex
        case .scriptHash: return try drep.id((.bech32, .cip129))
        }
    }

    static func anchor(_ anchor: Anchor?) -> (url: String, hash: String) {
        guard let anchor else { return ("", "") }
        return (anchor.anchorUrl.absoluteString, anchor.anchorDataHash.payload.hex)
    }

    static func pool(_ params: PoolParams) throws -> PoolRegistrationDraft {
        let reward = try Address(from: .bytes(params.rewardAccount.payload))
        let owners = try params.poolOwners.asArray.map { owner in
            try Address(stakingPart: .verificationKeyHash(owner), network: reward.network).toBech32()
        }
        let relays: [RelayDraft] = (params.relays ?? []).map { relay in
            switch relay {
            case .singleHostAddr(let host):
                if let ipv4 = host.ipv4 { return RelayDraft(kind: .ipv4, host: ipv4.address, port: host.port.map { UInt16($0) }) }
                return RelayDraft(kind: .ipv6, host: host.ipv6?.address ?? "", port: host.port.map { UInt16($0) })
            case .singleHostName(let host):
                return RelayDraft(kind: .dnsName, host: host.dnsName ?? "", port: host.port.map { UInt16($0) })
            case .multiHostName(let host):
                return RelayDraft(kind: .srvName, host: host.dnsName ?? "", port: nil)
            }
        }
        return PoolRegistrationDraft(
            pool: params.poolOperator.payload.hex,
            vrfKey: params.vrfKeyHash.payload.hex,
            pledge: UInt64(params.pledge),
            cost: UInt64(params.cost),
            // As a fraction, so it reads back exactly.
            margin: "\(params.margin.numerator)/\(params.margin.denominator)",
            rewardAccount: try reward.toBech32(),
            owners: owners,
            relays: relays,
            metadataURL: params.poolMetadata?.url?.absoluteString ?? "",
            metadataHash: params.poolMetadata?.poolMetadataHash?.payload.hex ?? ""
        )
    }
}

public enum CertificateFileError: Error, Sendable, Equatable, CustomStringConvertible {
    case notACertificate
    case needsNetwork
    case unsupported(String)

    public var description: String {
        switch self {
        case .notACertificate:
            "That is not a certificate: give a cardano-cli certificate file (a text envelope), or its CBOR."
        case .needsNetwork:
            "Choose the network first: the certificate's stake credential is shown as a stake address on it."
        case .unsupported(let reason):
            reason
        }
    }
}

extension CardanoNetwork {
    /// The address network: mainnet, or every testnet.
    var networkId: NetworkId { self == .mainnet ? .mainnet : .testnet }
}
