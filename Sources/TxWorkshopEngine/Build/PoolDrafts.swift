import Foundation
import SwiftCardanoCore
import TxWorkshopCore

extension TransactionComposer {
    /// The ledger's pool parameters for a pool registration draft.
    static func poolParams(_ draft: PoolRegistrationDraft) throws -> PoolParams {
        let vrf = try ValueReader.value(.vrfKeyHash, draft.vrfKey) { ComposeError.badGovernance("VRF key: \($0)") }
        guard let vrfBytes = try? TxDocumentCodec.bytes(fromHex: vrf), vrfBytes.count == 32 else {
            throw ComposeError.badGovernance("The VRF key hash is 32 bytes in hex.")
        }
        guard let pledge = draft.pledge else { throw ComposeError.badGovernance("Give the pool's pledge.") }
        guard let cost = draft.cost else { throw ComposeError.badGovernance("Give the pool's fixed cost.") }
        guard let margin = PoolMargin.parse(draft.margin) else {
            throw ComposeError.badGovernance("The margin \"\(draft.margin)\" is not a number from 0 to 1, a percentage or a fraction.")
        }
        let reward = try rewardAccount(draft.rewardAccount)
        let owners = try draft.owners.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { owner -> VerificationKeyHash in
            guard case .verificationKeyHash(let hash) = try stakeCredential(owner).credential else {
                throw ComposeError.badGovernance("\(owner): a pool owner is a stake key, not a script.")
            }
            return hash
        }
        return PoolParams(
            poolOperator: try poolKeyHash(draft.pool),
            vrfKeyHash: VrfKeyHash(payload: vrfBytes),
            pledge: Int(pledge),
            cost: Int(cost),
            margin: margin,
            rewardAccount: RewardAccountHash(payload: reward),
            poolOwners: .list(owners),
            relays: try draft.relays.map(relay),
            poolMetadata: try poolMetadata(draft.metadataURL, draft.metadataHash)
        )
    }

    static func relay(_ draft: RelayDraft) throws -> Relay {
        let host = draft.host.trimmingCharacters(in: .whitespaces)
        let port = draft.port.map(Int.init)
        switch draft.kind {
        case .ipv4:
            guard let address = IPv4Address(host) else { throw ComposeError.badGovernance("\(host) is not an IPv4 address.") }
            return .singleHostAddr(SingleHostAddr(port: port, ipv4: address, ipv6: nil))
        case .ipv6:
            guard let address = IPv6Address(host) else { throw ComposeError.badGovernance("\(host) is not an IPv6 address.") }
            return .singleHostAddr(SingleHostAddr(port: port, ipv4: nil, ipv6: address))
        case .dnsName:
            guard !host.isEmpty, host.utf8.count <= 64 else { throw ComposeError.badGovernance("A relay's DNS name is 1 to 64 bytes.") }
            return .singleHostName(SingleHostName(port: port, dnsName: host))
        case .srvName:
            guard !host.isEmpty, host.utf8.count <= 64 else { throw ComposeError.badGovernance("A relay's DNS name is 1 to 64 bytes.") }
            return .multiHostName(MultiHostName(dnsName: host))
        }
    }

    /// The registered metadata pointer; `nil` when both are empty.
    static func poolMetadata(_ url: String, _ hash: String) throws -> PoolMetadata? {
        let url = url.trimmingCharacters(in: .whitespaces)
        let hash = hash.trimmingCharacters(in: .whitespaces)
        if url.isEmpty, hash.isEmpty { return nil }
        guard url.utf8.count <= 64, let metadataURL = try? Url(url) else {
            throw ComposeError.badGovernance("The metadata URL must be a URL of at most 64 bytes.")
        }
        let hex = try ValueReader.value(.anchorHash, hash) { ComposeError.badGovernance("Metadata hash: \($0)") }
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), bytes.count == 32 else {
            throw ComposeError.badGovernance("The metadata hash is Blake2b-256 of the metadata file, 32 bytes in hex.")
        }
        return try PoolMetadata(url: metadataURL, poolMetadataHash: PoolMetadataHash(payload: bytes))
    }

    static func committeeCold(_ text: String) throws -> CommitteeColdCredential {
        let hex = try ValueReader.value(.committeeColdKeyHash, text) { ComposeError.badGovernance($0) }
        return CommitteeColdCredential(credential: .verificationKeyHash(try keyHash(hex)))
    }

    static func committeeHot(_ text: String) throws -> CommitteeHotCredential {
        let hex = try ValueReader.value(.committeeHotKeyHash, text) { ComposeError.badGovernance($0) }
        return CommitteeHotCredential(credential: .verificationKeyHash(try keyHash(hex)))
    }
}

/// A pool's margin, read from a decimal, a percentage or a fraction.
public enum PoolMargin {
    /// `text` as a reduced fraction from 0 to 1, or `nil`.
    public static func parse(_ text: String) -> UnitInterval? {
        var text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        var numerator: UInt64
        var denominator: UInt64
        if text.contains("/") {
            let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let n = UInt64(parts[0]), let d = UInt64(parts[1]), d > 0 else { return nil }
            (numerator, denominator) = (n, d)
        } else {
            var scale: UInt64 = 1
            if text.hasSuffix("%") {
                text.removeLast()
                scale = 100
            }
            let pieces = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
            guard (1...2).contains(pieces.count), pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }),
                let whole = UInt64(pieces[0].isEmpty ? "0" : pieces[0]) else { return nil }
            let fraction = pieces.count == 2 ? String(pieces[1]) : ""
            guard fraction.count <= 15 else { return nil }
            let places = UInt64(pow(10, Double(fraction.count)))
            numerator = whole * places + (UInt64(fraction.isEmpty ? "0" : fraction) ?? 0)
            denominator = places * scale
        }
        guard numerator <= denominator else { return nil }
        let divisor = gcd(numerator, denominator)
        return UnitInterval(numerator: numerator / divisor, denominator: denominator / divisor)
    }

    /// The margin as a decimal, as a form shows it.
    public static func text(_ margin: UnitInterval) -> String {
        guard margin.denominator > 0 else { return "0" }
        let value = Decimal(margin.numerator) / Decimal(margin.denominator)
        return "\(value)"
    }

    private static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 { b == 0 ? max(a, 1) : gcd(b, a % b) }
}
